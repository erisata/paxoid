%/--------------------------------------------------------------------
%| Copyright 2015-2016 Erisata, UAB (Ltd.)
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
-export([start/2, stop/1]).

%%% ============================================================================
%%% Callbacks for the application.
%%% ============================================================================

%%
%%
%%
start(_StartType, _StartArgs) ->
    paxoid_sup:start_link().

%%
%%
%%
stop(_State) ->
    ok.


