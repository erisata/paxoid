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
%%% The OPT application callback module.
%%%
-module(paxoid_app).
-behaviour(application).
-export([name/0, get_env/2]).
-export([start/2, stop/1]).

-define(APP, paxoid).


%%% ============================================================================
%%% Public API.
%%% ============================================================================

%%  @doc
%%  Returns name of this application.
%%
name() ->
    ?APP.


%%  @doc
%%  Retrieved a value of the environment variable for this application.
%%
get_env(Name, Default) ->
    application:get_env(?APP, Name, Default).



%%% ============================================================================
%%% Callbacks for the application.
%%% ============================================================================

%%  @doc
%%  Start this application.
%%
start(_StartType, _StartArgs) ->
    paxoid_sup:start_link().


%%  @doc
%%  Stop this application.
%%
stop(_State) ->
    ok.


