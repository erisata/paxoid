%%% @doc
%%% The master node for a distributed sequence.
%%%
%%% TODO: Timeouts, cleanup.
%%%
-module(paxoid).
-behaviour(gen_server).
-export([start_link/1, start_link/2, start_spec/1, join/2, next_id/1, info/1]).
-export([sync_info/5]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

-define(PART_SYNC_INTERVAL, 5000).

-type num() :: pos_integer().

-type step_round() :: {RandomInteger :: integer(), Node :: node()}.
-type step_value() :: node().
-type step_data()  :: {step_round(), step_value()}.

%%
%%
%%
start_link(Name) when is_atom(Name) ->
    start_link(Name, []).

start_link(Name, Nodes) when is_atom(Name), is_list(Nodes) ->
    gen_server:start_link({local, Name}, ?MODULE, {Name, Nodes}, []).


%%
%%
%%
start_spec(Name) ->
    paxoid_seq_sup:start_spec(Name).


%%
%%
%%
join(Name, Node) when is_atom(Node) ->
    join(Name, [Node]);

join(Name, Nodes) when is_list(Nodes) ->
    gen_server:cast(Name, {join, Nodes}).


%%
%%
%%
next_id(Name) ->
    gen_server:call(Name, {next_id}).


%%
%%
%%
info(Name) ->
    gen_server:call(Name, {info}).


%%% ============================================================================
%%% Paxos API for updating the sequence.
%%% ============================================================================

step_prepare(Name, StepNum, Partition, Round, ProposerNode) ->
    abcast = gen_server:abcast(Partition, Name, {step_prepare, StepNum, Round, ProposerNode, Partition}),
    ok.

step_prepared(Name, StepNum, ProposerNode, Accepted, AcceptorNode, Partition) ->
    ok = gen_server:cast({Name, ProposerNode}, {step_prepared, StepNum, Accepted, AcceptorNode, Partition}).

step_accept(Name, StepNum, Partition, Proposal) ->
    abcast = gen_server:abcast(Partition, Name, {step_accept, StepNum, Proposal, Partition}),
    ok.

step_accepted(Name, StepNum, Partition, Proposal, AcceptorNode) ->
    abcast = gen_server:abcast(Partition, Name, {step_accepted, StepNum, Proposal, AcceptorNode, Partition}),
    ok.


%%% ============================================================================
%%% Internal communication.
%%% ============================================================================

%%  @private
%%
%%
% step_col_started(Name, StepCol) ->
%     gen_server:cast(Name, {step_col_started, StepCol}).


%%  @private
%%  ...
%%
sync_info(Name, Node, Nodes, Max, TTL) ->
    _ = gen_server:abcast(Nodes, Name, {sync_info, Node, Nodes, Max, TTL}),
    ok.



%%% ============================================================================
%%% Internal state.
%%% ============================================================================

-record(step, {
    purpose      :: term(),                     % Purpose of the step.
    partition=[] :: [node()],                   % Partition in which the consensus should be reached.
    p_proposed   :: step_data() | undefined,    % PROPOSER: The current proposal.
    p_prms = []  :: [node()],                   % PROPOSER: Acceptor nodes, who promised to us.
    p_prm_max    :: step_data() | undefined,    % PROPOSER: Max proposal accepted by the acceptors.
    a_promise    :: step_round() | undefined,   % ACCEPTOR: Promise to not accept rounds =< this.
    a_accepted   :: step_data() | undefined,    % ACCEPTOR: Maximal accepted proposal.
    l_vals = #{} :: #{step_data() => [node()]}  % LEARNER:  Partially learned values.
}).

-record(state, {
    name    :: atom(),                          % Name of the sequence.
    node    :: node(),                          % The current node.
    nodes   :: [node()],                        % All known nodes.
    partn   :: #{node() => Time :: integer()},  % Nodes in te current partition.
    ids     :: [num()],                         % Known ids, allocated to this node.
    max     :: num(),                           % Maximal known ID (globally).
    map     :: #{Old :: num() => New :: num()}, % Mapping (Old -> New).
    %step_col:: pid(),   % TODO: Remove
    steps   :: #{Step :: num() => #step{}}
}).



%%% ============================================================================
%%% Callbacks for `gen_server'.
%%% ============================================================================

%%
%%
%%
init({Name, Nodes}) ->
    Node = node(),
    State = #state{
        name    = Name,
        node    = Node,
        nodes   = NewNodes = lists:usort([Node | Nodes]),
        partn   = #{},
        ids     = [],
        max     = Max = 0,
        map     = #{},
        steps   = #{}
    },
    ok = ?MODULE:sync_info(Name, Node, NewNodes, Max, 1),
    _ = erlang:send_after(?PART_SYNC_INTERVAL, self(), sync_timer),
    {ok, State}.


%%
%%
%%
handle_call({next_id}, From, State) ->
    NewState = step_request({reply, From}, State),
    {noreply, NewState};

handle_call({info}, _From, State = #state{nodes = Nodes, partn = Partn, ids = Ids, max = Max}) ->
    PartitionNodes = maps:keys(Partn),
    Info = #{
        other => Nodes -- PartitionNodes,
        partn => PartitionNodes,
        ids   => Ids,
        max   => Max
    },
    {reply, Info, State};


handle_call(Unknown, _From, State) ->
    {reply, {error, {unexpected_call, Unknown}}, State}.


%%
%%
%%
handle_cast({join, AddNodes}, State = #state{name = Name, node = Node, nodes = Nodes, max = Max}) ->
    NewNodes = lists:usort(AddNodes ++ Nodes),
    NewState = State#state{
        nodes = NewNodes
    },
    ok = ?MODULE:sync_info(Name, Node, NewNodes, Max, 1),
    {noreply, NewState};

% handle_cast({step_col_started, StepCol}, State) ->
%     NewState = State#state{
%         step_col = StepCol
%     },
%     {noreply, NewState};

handle_cast({sync_info, Node, Nodes, Max, TTL}, State = #state{name = Name, node = ThisNode, nodes = OldNodes, partn = Partn, max = OldMax}) ->
    Now      = erlang:monotonic_time(seconds),
    NewNodes = lists:usort(Nodes ++ OldNodes),
    NewMax   = erlang:max(Max, OldMax),
    NewState = State#state{
        nodes = NewNodes,
        max   = NewMax,
        partn = Partn#{Node => Now}
    },
    if TTL  >  0 -> ok = ?MODULE:sync_info(Name, ThisNode, NewNodes, NewMax, TTL - 1);
       TTL =:= 0 -> ok
    end,
    {noreply, NewState};

handle_cast({step_prepare, StepNum, Round, ProposerNode, Partition}, State = #state{name = Name, node = Node, steps = Steps}) ->
    % PAXOS(step): PROPOSER --prepare--> ACCEPTOR.
    Step = #step{
        partition  = OldPartition,
        a_promise  = Promise,
        a_accepted = Accepted
    } = maps:get(StepNum, Steps, #step{}),
    NewPartition = lists:usort(Partition ++ OldPartition),
    NewStep = case (Promise =:= undefined) orelse (Promise < Round) of
        true ->
            ok = step_prepared(Name, StepNum, ProposerNode, Accepted, Node, NewPartition),
            Step#step{
                partition = NewPartition,
                a_promise = Round
            };
        false ->
            Step#step{
                partition = NewPartition
            }
    end,
    {noreply, State#state{steps = Steps#{StepNum => NewStep}}};

handle_cast({step_prepared, StepNum, Accepted, AcceptorNode, Partition}, State = #state{name = Name, steps = Steps}) ->
    % PAXOS(step): ACCEPTOR --prepared--> PROPOSER.
    Step = #step{
        partition  = OldPartition,
        p_proposed = Proposed = {Round, _},
        p_prms     = Promised,
        p_prm_max  = MaxAccepted
    } = maps:get(StepNum, Steps, #step{}),
    NewPartition = lists:usort(Partition ++ OldPartition),
    NewPromised = lists:usort([AcceptorNode | Promised]),
    NewAccepted = case {MaxAccepted, Accepted} of
        {undefined, undefined} -> undefined;
        {undefined, _        } -> Accepted;
        {_,         undefined} -> MaxAccepted;
        {_,         _        } -> erlang:max(Accepted, MaxAccepted)
    end,
    NewStep = Step#step{
        partition = NewPartition,
        p_prms    = NewPromised,
        p_prm_max = NewAccepted
    },
    case length(NewPromised) * 2 > length(NewPartition) of
        true ->
            Proposal = case NewAccepted of
                undefined   -> Proposed;
                {_, AccVal} -> {Round, AccVal}
            end,
            ok = step_accept(Name, StepNum, NewPartition, Proposal);
        false ->
            ok
    end,
    {noreply, State#state{steps = Steps#{StepNum => NewStep}}};

handle_cast({step_accept, StepNum, Proposal = {Round, _Value}, Partition}, State = #state{name = Name, node = Node, steps = Steps}) ->
    Step = #step{
        partition = OldPartition,
        a_promise = Promise
    } = maps:get(StepNum, Steps, #step{}),
    NewPartition = lists:usort(Partition ++ OldPartition),
    NewStep = case Round >= Promise of
        true ->
            ok = step_accepted(Name, StepNum, NewPartition, Proposal, Node),
            Step#step{
                partition  = NewPartition,
                a_accepted = Proposal
            };
        false ->
            Step#step{
                partition  = NewPartition
            }
    end,
    {noreply, State#state{steps = Steps#{StepNum => NewStep}}};

handle_cast({step_accepted, StepNum, Proposal = {_Round, Value}, AcceptorNode, Partition}, State) ->
    #state{
        node  = Node,
        max   = Max,
        ids   = Ids,
        steps = Steps
    } = State,
    Step = #step{
        purpose    = Purpose,
        partition  = OldPartition,
        l_vals     = LearnedValues
    } = maps:get(StepNum, Steps, #step{}),
    NewAccepted = lists:usort([AcceptorNode | maps:get(Proposal, LearnedValues, [])]),
    NewLearnedValues = LearnedValues#{Proposal => NewAccepted},
    NewPartition = lists:usort(Partition ++ OldPartition),
    NewStep = Step#step{
        partition = NewPartition,
        l_vals    = NewLearnedValues
    },
    NewState = case length(NewAccepted) * 2 > length(NewPartition) of
        true ->
            case {Value, Purpose} of
                {Node, _} ->
                    % Have a number assigned to our node, lets use it.
                    case Purpose of
                        undefined       -> ok;
                        {reply, Caller} -> gen_server:reply(Caller, StepNum)
                    end,
                    State#state{
                        ids   = lists:usort([StepNum | Ids]),
                        max   = erlang:max(Max, StepNum),
                        steps = Steps#{StepNum => NewStep#step{purpose = undefined}}
                    };
                {_, undefined} ->
                    % The step was initiated by other node, so we
                    % just update our max value.
                    State#state{
                        max   = erlang:max(Max, StepNum),
                        steps = Steps#{StepNum => NewStep}
                    };
                {_, _} ->
                    % The step was initiated by this node, so we need to
                    % attempt to get new step allocated to this node.
                    TmpState = State#state{
                        max   = erlang:max(Max, StepNum),
                        steps = Steps#{StepNum => NewStep#step{purpose = undefined}}
                    },
                    step_request(Purpose, TmpState)
            end;
        false ->
            State#state{
                steps = Steps#{StepNum => NewStep}
            }
    end,
    {noreply, NewState};

handle_cast(Unknown, State) ->
    error_logger:warning_msg("Unknown cast: ~p~n", [Unknown]),
    {noreply, State}.


%%
%%
%%
handle_info(sync_timer, State = #state{name = Name, node = Node, nodes = Nodes, partn = Partn, max = Max}) ->
    Now = erlang:monotonic_time(seconds),
    NewPartn = maps:filter(fun (_, NodeTime) ->
        (Now - NodeTime) > (?PART_SYNC_INTERVAL * 2)
    end, Partn#{Node => Now}),
    ok = ?MODULE:sync_info(Name, Node, Nodes, Max, 1),
    _ = erlang:send_after(?PART_SYNC_INTERVAL, self(), sync_timer),
    NewState = State#state{
        partn = NewPartn
    },
    {noreply, NewState};

handle_info(Unknown, State) ->
    error_logger:warning_msg("Unknown info: ~p~n", [Unknown]),
    {noreply, State}.

%%
%%
%%
terminate(_Reason, _State) ->
    ok.


%%
%%
%%
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.



%%% ============================================================================
%%% Internal functions.
%%% ============================================================================

step_request(Purpose, State) ->
    #state{
        name  = Name,
        node  = Node,
        max   = Max,
        partn = Partn,
        steps = Steps
    } = State,
    StepNum   = lists:max([Max | maps:keys(Steps)]) + 1,
    Partition = maps:keys(Partn),
    Round     = {rand:uniform(), Node},
    ok = step_prepare(Name, StepNum, Partition, Round, Node),
    NewStep = #step{
        purpose    = Purpose,
        partition  = Partition,
        p_proposed = {Round, Node}
    },
    State#state{
        steps = Steps#{StepNum => NewStep}
    }.


