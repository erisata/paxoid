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
%%% Supervises all the paxoid processes, that are not running in the
%%% context of the user application.
%%%
-module(paxoid_col).
-behaviour(supervisor).
-export([start_link/0, start_child/1, start_child/2]).
-export([init/1]).


%%% ============================================================================
%%% API functions.
%%% ============================================================================

%%  @doc
%%
%%
start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).


%%  @doc
%%  Add new supervised paxoid process.
%%
start_child(Name) ->
    start_child(Name, []).

start_child(Name, Nodes) ->
    supervisor:start_child(?MODULE, paxoid:start_spec(Name, Nodes)).



%%% ============================================================================
%%% Callbacks for `supervisor'.
%%% ============================================================================

%%  @private
%%
%%
init([]) ->
    SupFlags = #{
        strategy  => one_for_one,
        intensity => 10,
        period    => 10
    },
    Predefined = paxoid_app:get_env(predefined, []),
    {ok, {SupFlags, lists:map(fun child_spec/1, Predefined)}}.


%%
%%
%%
child_spec(Name) when is_atom(Name) ->
    paxoid:start_spec(Name, []);

child_spec({Name, Nodes}) when is_atom(Name), is_list(Nodes) ->
    paxoid:start_spec(Name, Nodes).


