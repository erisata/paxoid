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
%%% The main supervisor of the application.
%%%
-module(paxoid_sup).
-behaviour(supervisor).
-export([start_link/0]).
-export([init/1]).

%%% ============================================================================
%%% API functions.
%%% ============================================================================

%%  @doc
%%
%%
start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).



%%% ============================================================================
%%% Callbacks for `supervisor'.
%%% ============================================================================

%%  @private
%%
%%
init([]) ->
    SupFlags = #{
        strategy  => one_for_all,
        intensity => 10,
        period    => 10
    },
    {ok, {SupFlags, []}}.


