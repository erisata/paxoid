%/--------------------------------------------------------------------
%| Copyright 2019 Erisata, UAB (Ltd.)
%|
%| Licensed under the Apache License, Version 2.0 (the "License");
%| you may not use this file except in compliance with the License.
%| You may obtain a copy of the License at
%|
%|     http://www.apache.org/licenses/LICENSE-2.0
%|
%| Unless required by applicable law or agreed to in writing, software
%| distributed under the License is distributed on an "AS IS" BASIS,
%| WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%| See the License for the specific language governing permissions and
%| limitations under the License.
%\--------------------------------------------------------------------

%%% @private
%%% A Common Test suite for the Paxoid application.
%%%
-module(paxoid_SUITE).
-export([all/0, init_per_suite/1, end_per_suite/1]).
-export([do_next_id_seq/2]).
-export([
    test_simple/1,
    test_burst/1,
    test_join/1,
    test_file/1,
    test_majority_down/1
]).
-include_lib("kernel/include/inet.hrl").
-include_lib("common_test/include/ct.hrl").


%%% ============================================================================
%%% Callbacks for CT.
%%% ============================================================================

%%
%%  Returns a list containing all test case names.
%%
all() ->
    [
        test_simple,
        test_burst,
        test_join,
        test_file,
        test_majority_down
    ].

%%
%%  Initialization.
%%
init_per_suite(Config) ->
    case node() of
        'nonode@nohost' -> os:cmd("epmd -daemon"), net_kernel:start([?MODULE, longnames]);
        _               -> ok
    end,
    {ok, _} = application:ensure_all_started(sasl),
    ct:pal("Starting slave nodes...~n"),
    LocalNodeNames = [
        paxoid_SUITE_A,
        paxoid_SUITE_B,
        paxoid_SUITE_C
    ],
    lists:foreach(fun (LocalNodeName) ->
        pang = net_adm:ping(node_name(LocalNodeName))
    end, LocalNodeNames),
    {ok, Nodes} = start_nodes(LocalNodeNames, Config),
    ct:pal("Starting slave nodes... done, nodes=~p~n", [Nodes]),
    [{started_apps, []}, {started_nodes, Nodes} | Config].


%%
%%  Cleanup.
%%
end_per_suite(Config) ->
    [ ok = application:stop(App) || App  <- proplists:get_value(started_apps,  Config)],
    ok = stop_nodes(proplists:get_value(started_nodes, Config)),
    ok.


%%% ============================================================================
%%% Helper functions.
%%% ============================================================================

%%
%%  Gets a hostname of the current node.
%%
this_host() ->
    {ok, ShortHostname} = inet:gethostname(),
    {ok, #hostent{h_name = FullHostname}} = inet:gethostbyname(ShortHostname),
    FullHostname.


%%
%%  Extract the local part from the node name.
%%
local_name(Node) ->
    case re:run(erlang:atom_to_list(Node), "^(.*?)@", [{capture, all_but_first, list}]) of
        {match, [LocalStr]} -> erlang:list_to_atom(LocalStr);
        nomatch             -> Node
    end.

%%
%%
%%
node_name(Node) ->
    case re:run(erlang:atom_to_list(Node), "^(.*?)@", [{capture, none}]) of
        match   -> Node;
        nomatch -> erlang:list_to_atom(erlang:atom_to_list(Node) ++ "@" ++ this_host())
    end.


%%
%%
%%
start_nodes(Nodes, _Config) ->
    ThisHost = this_host(),
    StartedNodes = lists:map(fun (Node) ->
        {ok, NodeName} = slave:start(ThisHost, local_name(Node)),
        NodeName
    end, Nodes),
    StartedNodeCount = length(StartedNodes),
    CodePath = lists:filter(fun filelib:is_dir/1, code:get_path()),
    {ResPath,  []} = rpc:multicall(StartedNodes, code, set_path, [CodePath]),                 % true
    {ResStart, []} = rpc:multicall(StartedNodes, application, ensure_all_started, [paxoid]),  % {ok, _}
    StartedNodeCount = length([ok || true    <- ResPath]),
    StartedNodeCount = length([ok || {ok, _} <- ResStart]),
    {ok, lists:sort(StartedNodes)}.


%%
%%
%%
stop_nodes(Nodes) ->
    [ ok = slave:stop(Node) || Node <- Nodes],
    ok.


%%
%%  Used to run a sequence of calls on the remote server.
%%
do_next_id_seq(Name, Count) ->
    lists:map(fun (_) -> paxoid:next_id(Name) end, lists:seq(1, Count)).



%%% ============================================================================
%%% Test cases.
%%% ============================================================================

%%
%%  Check, if unique IDs are generated in the cluster.
%%
test_simple(Config) ->
    Nodes = proplists:get_value(started_nodes, Config),
    {[{ok, _}, {ok, _}, {ok, _}], []} = rpc:multicall(Nodes, paxoid, start_sup, [?FUNCTION_NAME, #{join => Nodes}]),
    {Ids,                         []} = rpc:multicall(Nodes, paxoid, next_id,   [?FUNCTION_NAME]),
    [1, 2, 3] = lists:sort(Ids),
    ok.


%%
%%  Check if several parallel bursts are producing unique IDs.
%%
test_burst(Config) ->
    Count = 2000,
    Nodes = proplists:get_value(started_nodes, Config),
    {[{ok, _}, {ok, _}, {ok, _}], []} = rpc:multicall(Nodes, paxoid, start_sup, [?FUNCTION_NAME, #{join => Nodes}]),
    {Ids,                         []} = rpc:multicall(Nodes, ?MODULE, do_next_id_seq, [?FUNCTION_NAME, Count]),
    ok = fun
        F([A, B | C]) -> B = A + 1, F([B | C]);
        F([_])        -> F([]);
        F([])         -> ok
    end(lists:sort(lists:append(Ids))),
    6000 = length(lists:append(Ids)),
    6000 = length(lists:usort(lists:append(Ids))),
    ExpectedIds = lists:seq(1, Count * 3),
    ExpectedIds = lists:sort(lists:append(Ids)),
    ok.


%%
%%  Check, if nodes with the same IDs can be joined together.
%%
test_join(Config) ->
    [NodeA | _] = Nodes = proplists:get_value(started_nodes, Config),
    %
    % Start nodes in a disconnected mode (3 separate clusters of 1 node).
    {[{ok, _}, {ok, _}, {ok, _}], []} = rpc:multicall(Nodes, paxoid, start_sup, [?FUNCTION_NAME]),
    {[ok,      ok,      ok     ], []} = rpc:multicall(Nodes, paxoid, start,     [?FUNCTION_NAME]),
    {Ids,                         []} = rpc:multicall(Nodes, ?MODULE, do_next_id_seq, [?FUNCTION_NAME, 3]),
    9         = length(lists:append(Ids)),      % We should have 9 ids in total.
    [1, 2, 3] = lists:usort(lists:append(Ids)), % Now ids are duplicated, nodes are not joined yet.
    %
    % Merge the nodes
    ok = rpc:call(NodeA, paxoid, join, [?FUNCTION_NAME, Nodes]),
    WaitForJoin = fun WaitForJoin() ->
        {Infos, []} = rpc:multicall(Nodes, paxoid, info, [?FUNCTION_NAME]),
        AllMerged = fun ({ok, #{partition := Partition}}) ->
            [] =:= Nodes -- Partition
        end,
        case lists:all(AllMerged, Infos) of
            true -> ok;
            false -> timer:sleep(100), WaitForJoin()
        end
    end,
    WaitForJoin(),
    %
    % Check, if IDs are unique after the merge.
    {NewInfos, []} = rpc:multicall(Nodes, paxoid, info, [?FUNCTION_NAME]),
    ct:pal("NewInfos: ~p~n", [NewInfos]),
    9 = length(lists:usort(lists:append([NewIds || {ok, #{ids := NewIds}} <- NewInfos]))),
    ok.


%%
%%  Check if the file based callback works.
%%
test_file(Config) ->
    Nodes = proplists:get_value(started_nodes, Config),
    Opts = #{
        join     => Nodes,
        callback => paxoid_cb_file
    },
    %
    % Produce some IDs.
    {[{ok, _}, {ok, _}, {ok, _}], []} = rpc:multicall(Nodes, paxoid, start_sup, [?FUNCTION_NAME, Opts]),
    {Ids,                         []} = rpc:multicall(Nodes, paxoid, next_id,   [?FUNCTION_NAME]),
    [1, 2, 3] = lists:sort(Ids),
    %
    % Restart the nodes.
    ok = stop_nodes(Nodes),
    {ok, Nodes} = start_nodes(Nodes, Config),
    %
    % Produce some more ids, use known nodes from a file..
    {[{ok, _}, {ok, _}, {ok, _}], []} = rpc:multicall(Nodes, paxoid, start_sup, [?FUNCTION_NAME, Opts#{join => []}]),
    {NewIds,                      []} = rpc:multicall(Nodes, paxoid, next_id,   [?FUNCTION_NAME]),
    [4, 5, 6] = lists:sort(NewIds),
    %
    % Check, if all the history is returned.
    {Infos, []} = rpc:multicall(Nodes, paxoid, info, [?FUNCTION_NAME]),
    [1, 2, 3, 4, 5, 6] = lists:sort(lists:append([I || {ok, #{ids := I}} <- Infos])),
    ok.


%%
%%  Check if the IDs can be generated while majority is unreachable.
%%
test_majority_down(Config) ->
    Nodes = proplists:get_value(started_nodes, Config),
    Opts = #{
        join => Nodes
    },
    %
    % Produce some IDs.
    {[{ok, _}, {ok, _}, {ok, _}], []} = rpc:multicall(Nodes, paxoid, start_sup, [?FUNCTION_NAME, Opts]),
    {Ids,                         []} = rpc:multicall(Nodes, paxoid, next_id,   [?FUNCTION_NAME]),
    [1, 2, 3] = lists:sort(Ids),
    %
    % Stop the nodes.
    [LuckyNode | UnluckyNodes] = Nodes,
    ok = stop_nodes(UnluckyNodes),
    %
    % Produce some more ids, use known nodes from a file..
    4 = rpc:call(LuckyNode, paxoid, next_id, [?FUNCTION_NAME]),
    %
    % TODO: Restart nodes.
    {ok, _} = start_nodes(UnluckyNodes, Config),
    ok.


