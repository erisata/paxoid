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
%%% Callback module for `paxoid', storing all the state in memory.
%%% Most likely you will use this module as an example on how
%%% to implement own callback.
%%%
-module(paxoid_cb_mem).
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
    ids :: [paxoid:num()],
    max :: paxoid:num(),
    map :: #{Old :: paxoid:num() => New :: paxoid:num()}
}).



%%% ============================================================================
%%% Callbacks for `paxoid'.
%%% ============================================================================

%%  @doc
%%  Initializes this callback.
%%
init(Args) ->
    Max = maps:get(max, Args, 0),
    Ids = maps:get(ids, Args, []),
    State = #state{
        ids = Ids,
        max = Max,
        map = #{}
    },
    {ok, Max, State}.


%%
%%
%%
describe(State = #state{ids = Ids}) ->
    Info = #{ids => Ids},
    {ok, Info, State}.


%%
%%
%%
handle_new_id(NewId, State = #state{max = Max, ids = Ids}) ->
    NewState = State#state{
        max = erlang:max(NewId, Max),
        ids = [NewId | Ids]
    },
    {ok, NewState}.


%%
%%
%%
handle_new_map(OldId, NewId, State = #state{max = Max, ids = Ids, map = Map}) ->
    MapId = fun
        (Id) when Id =:= OldId -> NewId;
        (Id)                   -> Id
    end,
    NewState = State#state{
        max = erlang:max(NewId, Max),
        ids = lists:map(MapId, Ids),
        map = Map#{OldId => NewId}
    },
    {ok, NewState}.


%%
%%
%%
handle_new_max(NewMax, State) ->
    NewState = State#state{
        max = NewMax
    },
    {ok, NewState}.



%%  @doc
%%  Returns a requested range of IDs owned by this node.
%%
handle_select(From, Till, MaxCount, State = #state{ids = Ids}) ->
    SelectIds = fun
        SelectIds([Id | Other], Count, AccIds) ->
            if  Count =< 0 -> {ok, hd(AccIds), lists:reverse(AccIds), State};   % Overflow by size.
                Id > Till  -> {ok, Till, lists:reverse(AccIds), State};         % Range scanned.
                Id < From  -> SelectIds(Other, Count, AccIds);                  % Skip the first ids.
                true       -> SelectIds(Other, Count - 1, [Id | AccIds])        % Collect them.
            end;
        SelectIds([], _Count, AccIds) ->
            {ok, Till, lists:reverse(AccIds), State}                            % Covered all the requested range.
    end,
    SelectIds(lists:usort(Ids), MaxCount, []).


%%  @doc
%%  Checks if provided list of IDs has numbers conflicting with this node.
%%
handle_check(PeerIds, State = #state{ids = Ids}) ->
    DuplicatedIds = lists:filter(fun (Id) ->
        lists:member(Id, Ids)
    end, PeerIds),
    {ok, DuplicatedIds, State}.


