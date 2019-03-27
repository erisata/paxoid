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

%%% @doc
%%% Callback module for `paxoid', storing all the state in a file.
%%% The file is the plain-text one, used with `file:consult/*'.
%%% Most likely you will use this module as an example on how
%%% to implement own callback with persistence.
%%%
-module(paxoid_cb_file).
-behaviour(paxoid).
-export([
    init/1,
    describe/1,
    handle_new_id/2,
    handle_new_map/3,
    handle_new_max/2,
    handle_select/4,
    handle_check/2
]).


%%% ============================================================================
%%% Internal state.
%%% ============================================================================

%%
%%  The state for this callback module.
%%
-record(state, {
    file :: file:filename(),
    mem  :: term()
}).



%%% ============================================================================
%%% Callbacks for `paxoid'.
%%% ============================================================================

%%  @doc
%%  Initializes this callback.
%%
init(Args) ->
    Filename = maps:get(filename, Args, "paxoid.db-" ++ erlang:atom_to_list(node())),
    MemArgs = case file:consult(Filename) of
        {ok, Terms} ->
            error_logger:info_msg("Initial state was read from a local paxoid file=~p~n", [Filename]),
            InitIds =            proplists:get_value(ids, Terms, maps:get(ids, Args, [])),
            InitMax = lists:max([proplists:get_value(max, Terms, maps:get(max, Args, 0)) | InitIds]),
            Args#{
                max => InitMax,
                ids => InitIds,
                map => proplists:get_value(map, Terms, maps:get(map, Args, #{}))
            };
        {error, Reason} ->
            error_logger:warning_msg("Unable to read local paxoid file=~p, reason=~p~n", [Filename, Reason]),
            Args
    end,
    {ok, Max, MemState} = paxoid_cb_mem:init(MemArgs),
    State = #state{
        file = Filename,
        mem  = MemState
    },
    {ok, Max, save(State)}.


%%
%%
%%
describe(State = #state{mem = MemState}) ->
    {ok, Info, NewMemState} = paxoid_cb_mem:describe(MemState),
    {ok, Info, State#state{mem = NewMemState}}.


%%
%%
%%
handle_new_id(NewId, State = #state{mem = MemState}) ->
    {ok, NewMemState} = paxoid_cb_mem:handle_new_id(NewId, MemState),
    {ok, save(State#state{mem = NewMemState})}.


%%
%%
%%
handle_new_map(OldId, NewId, State = #state{mem = MemState}) ->
    {ok, NewMemState} = paxoid_cb_mem:handle_new_map(OldId, NewId, MemState),
    {ok, save(State#state{mem = NewMemState})}.


%%
%%
%%
handle_new_max(NewMax, State = #state{mem = MemState}) ->
    {ok, NewMemState} = paxoid_cb_mem:handle_new_max(NewMax, MemState),
    {ok, save(State#state{mem = NewMemState})}.



%%  @doc
%%  Returns a requested range of IDs owned by this node.
%%
handle_select(From, Till, MaxCount, State = #state{mem = MemState}) ->
    {ok, ResTill, ResIds, NewMemState} = paxoid_cb_mem:handle_select(From, Till, MaxCount, MemState),
    {ok, ResTill, ResIds, State#state{mem = NewMemState}}.


%%  @doc
%%  Checks if provided list of IDs has numbers conflicting with this node.
%%
handle_check(PeerIds, State = #state{mem = MemState}) ->
    {ok, DuplicatedIds, NewMemState} = paxoid_cb_mem:handle_check(PeerIds, MemState),
    {ok, DuplicatedIds, State#state{mem = NewMemState}}.



%%% ============================================================================
%%% Internal functions.
%%% ============================================================================

%%
%%
%%
save(State = #state{file = Filename, mem = MemState}) ->
    {ok, Max, Ids, Map} = paxoid_cb_mem:extract_data(MemState),
    ok = file:write_file(Filename, io_lib:format(
        "{max, ~p}.~n{ids, ~p}.~n{map, ~p}.~n",
        [Max, Ids, Map]
    )),
    State.


