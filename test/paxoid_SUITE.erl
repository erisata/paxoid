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
    test_join/1
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
        test_join
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
    {ok, ThisHost} = this_host(),
    ct:pal("Starting slave nodes...~n"),
    pang = net_adm:ping(erlang:list_to_atom("paxoid_SUITE_A" ++ "@" ++ ThisHost)),
    pang = net_adm:ping(erlang:list_to_atom("paxoid_SUITE_B" ++ "@" ++ ThisHost)),
    pang = net_adm:ping(erlang:list_to_atom("paxoid_SUITE_C" ++ "@" ++ ThisHost)),
    {ok, NodeA} = slave:start(ThisHost, paxoid_SUITE_A),
    {ok, NodeB} = slave:start(ThisHost, paxoid_SUITE_B),
    {ok, NodeC} = slave:start(ThisHost, paxoid_SUITE_C),
    Nodes    = [NodeA, NodeB, NodeC],
    CodePath = lists:filter(fun filelib:is_dir/1, code:get_path()),
    {[true,    true,    true   ], []} = rpc:multicall(Nodes, code, set_path, [CodePath]),
    {[{ok, _}, {ok, _}, {ok, _}], []} = rpc:multicall(Nodes, application, ensure_all_started, [paxoid]),
    ct:pal("Starting slave nodes... done, nodes=~p~n", [Nodes]),
    [{started_apps, []}, {started_nodes, Nodes} | Config].


%%
%%  Cleanup.
%%
end_per_suite(Config) ->
    [ ok = application:stop(App) || App  <- proplists:get_value(started_apps,  Config)],
    [ ok = slave:stop(Node)      || Node <- proplists:get_value(started_nodes, Config)],
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
    {ok, FullHostname}.


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
    {[{ok, _}, {ok, _}, {ok, _}], []} = rpc:multicall(Nodes, paxoid, start_sup, [?FUNCTION_NAME, Nodes]),
    {Ids,                         []} = rpc:multicall(Nodes, paxoid, next_id,   [?FUNCTION_NAME]),
    [1, 2, 3] = lists:sort(Ids),
    ok.


%%
%%  Check if several parallel bursts are producing unique IDs.
%%
test_burst(Config) ->
    Count = 2000,
    Nodes = proplists:get_value(started_nodes, Config),
    {[{ok, _}, {ok, _}, {ok, _}], []} = rpc:multicall(Nodes, paxoid, start_sup, [?FUNCTION_NAME, Nodes]),
    {Ids,                         []} = rpc:multicall(Nodes, ?MODULE, do_next_id_seq, [?FUNCTION_NAME, Count]),
    ct:pal("IDS: ~p~n", [Ids]),
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
    {[{ok, _}, {ok, _}, {ok, _}], []} = rpc:multicall(Nodes, paxoid, start_sup, [?FUNCTION_NAME, []]),
    {[ok,      ok,      ok     ], []} = rpc:multicall(Nodes, paxoid, start,     [?FUNCTION_NAME]),
    {Ids,                         []} = rpc:multicall(Nodes, ?MODULE, do_next_id_seq, [?FUNCTION_NAME, 3]),
    9         = length(lists:append(Ids)),      % We should have 9 ids in total.
    [1, 2, 3] = lists:usort(lists:append(Ids)), % Now ids are duplicated, nodes are not joined yet.
    %
    % Merge the nodes
    ok = rpc:call(NodeA, paxoid, join, [?FUNCTION_NAME, Nodes]),
    WaitForJoin = fun WaitForJoin() ->
        {Infos, []} = rpc:multicall(Nodes, paxoid, info, [?FUNCTION_NAME]),
        AllMerged = fun (#{partition := Partition}) ->
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
    {NewIds, []} = rpc:multicall(Nodes, ?MODULE, do_next_id_seq, [?FUNCTION_NAME, 3]),
    9 = length(lists:usort(lists:append(NewIds))),
    ok.


