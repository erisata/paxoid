%%% @doc
%%% The master node for a distributed sequence.
%%%
-module(paxoid).
-behaviour(gen_server).
-export([start_link/1, start_link/2, start_spec/1, join/2, next_id/1, next_id/2, info/1]).
-export([sync_info/5]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

-define(PART_SYNC_INTERVAL, 5000).
-define(DEFAULT_RETRY,      1000).
-define(DEFAULT_TIMEOUT,    5000).
-define(MAX_JOIN_SYNC_SIZE, 1000).

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
    next_id(Name, ?DEFAULT_TIMEOUT).

next_id(Name, Timeout) ->
    gen_server:call(Name, {next_id, Timeout}, Timeout).


%%
%%
%%
info(Name) ->
    gen_server:call(Name, {info}).




%%% ============================================================================
%%% Internal communication.
%%% ============================================================================

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
    purpose        :: term(),                     % Purpose of the step (~callback).
    ref            :: reference() | timeout | chosen, % ...
    giveup_time    :: integer(),
    giveup_tref    :: reference(),
    retry_tref     :: reference(),
    partition = [] :: [node()],                   % Partition in which the consensus should be reached.
    p_proposed     :: step_data() | undefined,    % PROPOSER: The current proposal.
    p_prms = []    :: [node()],                   % PROPOSER: Acceptor nodes, who promised to us.
    p_prm_max      :: step_data() | undefined,    % PROPOSER: Max proposal accepted by the acceptors.
    a_promise      :: step_round() | undefined,   % ACCEPTOR: Promise to not accept rounds =< this.
    a_accepted     :: step_data() | undefined,    % ACCEPTOR: Maximal accepted proposal.
    l_vals = #{}   :: #{step_data() => [node()]}  % LEARNER:  Partially learned values.
}).

-record(join, {
    node    :: node(),
    ref     :: reference(),
    from    :: num(),
    till    :: num(),
    dup_ids :: [num()]
}).

-record(state, {
    name    :: atom(),                          % Name of the sequence.
    node    :: node(),                          % The current node.
    mode    :: joining | active,                % ... ?????????? TODO
    reqs    :: [term()],                        % Pending requests? TODO
    known   :: [node()],                        % All known nodes.
    seen    :: #{node() => Time :: integer()},  % All seen nodes, not yet joined to the partition (`keys(seen) \subseteq known').
    part    :: [node()],                        % Nodes in te current partition (`part \subseteq keys(seen)').
    ids     :: [num()],                         % Known ids, allocated to this node.
    min     :: num(),                           % Mimimal choosable ID (exclusive).
    max     :: num(),                           % Maximal known chosen ID (inclusive, globally).
    map     :: #{Old :: num() => New :: num()}, % Mapping (Old -> New).
    retry   :: integer(),                       % Retry period.
    steps   :: #{Step :: num() => #step{}},
    joining :: #{Node :: node() => #join{}},    % All the ongoing join processes.
    dup_ids :: [num()]                          % All known duplicated ids. The must be mapped.
}).



%%% ============================================================================
%%% Callbacks for `gen_server'.
%%% ============================================================================

%%
%%
%%
init({Name, Nodes}) ->
    Now  = erlang:monotonic_time(seconds),
    Node = node(),
    Max  = 0,
    State = #state{
        name    = Name,
        node    = Node,
        mode    = joining,
        known   = Known = lists:usort([Node | Nodes]),
        seen    = #{Node => Now},
        part    = [Node],
        ids     = [],
        min     = Max,
        max     = Max,
        map     = #{},
        retry   = ?DEFAULT_RETRY,
        steps   = #{}
    },
    ok = ?MODULE:sync_info(Name, Node, Known, Max, 1),
    _ = erlang:send_after(?PART_SYNC_INTERVAL, self(), sync_timer),
    {ok, State}.


%%
%%
%%
handle_call({next_id, Timeout}, From, State) ->
    NewState = step_do_initialize({reply, From}, Timeout, State),
    {noreply, NewState};

handle_call({info}, _From, State = #state{known = Known, seen = Seen, part = Part, ids = Ids, min = Min, max = Max}) ->
    SeenNodes = maps:keys(Seen),
    Info = #{
        offline   => Known -- SeenNodes,
        joining   => join_pending(State),
        partition => Part,
        ids       => Ids,
        min       => Min,
        max       => Max
    },
    {reply, Info, State};


handle_call(Unknown, _From, State) ->
    {reply, {error, {unexpected_call, Unknown}}, State}.


%%
%%
%%
handle_cast({join, Nodes}, State = #state{name = Name, node = Node, known = Known, max = Max}) ->
    NewKnown = lists:usort(Nodes ++ Known),
    NewState = State#state{
        known = NewKnown
    },
    ok = ?MODULE:sync_info(Name, Node, NewKnown, Max, 1),
    {noreply, NewState};

handle_cast({sync_info, Node, Nodes, Max, TTL}, State = #state{name = Name, node = ThisNode, known = Known, seen = Seen, max = OldMax}) ->
    Now      = erlang:monotonic_time(seconds),
    NewKnown = lists:usort(Nodes ++ Known),
    NewMax   = erlang:max(Max, OldMax),
    TmpState = State#state{
        known = NewKnown,
        seen  = Seen#{Node => Now, ThisNode => Now},
        max   = NewMax
    },
    NewState = join_start_if_needed(TmpState),
    if TTL  >  0 -> ok = ?MODULE:sync_info(Name, ThisNode, NewKnown, NewMax, TTL - 1);
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
        purpose     = Purpose,
        partition   = OldPartition,
        l_vals      = LearnedValues
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
                    TmpState = State#state{
                        ids   = lists:usort([StepNum | Ids]),
                        max   = erlang:max(Max, StepNum),
                        steps = Steps#{StepNum => NewStep#step{purpose = undefined, ref = chosen}}
                    },
                    case Purpose of
                        undefined       -> TmpState;
                        {reply, Caller} -> gen_server:reply(Caller, StepNum), TmpState;
                        {join,  DupId}  -> join_sync_id_allocated(DupId, StepNum, TmpState)
                    end;
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
                    % Do not mark this step for archiving, because we are
                    % not the only proposer.
                    TmpState = State#state{
                        max = erlang:max(Max, StepNum)
                    },
                    step_do_next_attempt(StepNum, TmpState)
            end;
        false ->
            State#state{
                steps = Steps#{StepNum => NewStep}
            }
    end,
    {noreply, NewState};

handle_cast({join_sync_req, PeerNode, From, Till, MaxSize}, State) ->
    NewState = join_sync_req(PeerNode, From, Till, MaxSize, State),
    {noreply, NewState};

handle_cast({join_sync_res, PeerNode, From, Till, PeerIds}, State) ->
    NewState = join_sync_res(PeerNode, From, Till, PeerIds, State),
    {noreply, NewState};

handle_cast(Unknown, State) ->
    error_logger:warning_msg("Unknown cast: ~p~n", [Unknown]),
    {noreply, State}.


%%
%%
%%
handle_info(sync_timer, State = #state{name = Name, node = Node, known = Known, seen = Seen, part = Part, max = Max}) ->
    %
    % Update the list of seen nodes.
    Now = erlang:monotonic_time(seconds),
    NewSeen = maps:filter(fun (_, NodeTime) ->
        (Now - NodeTime) > (?PART_SYNC_INTERVAL * 2)
    end, Seen#{Node => Now}),
    %
    % Shrink our partition, if some nodes become unreachable.
    NewPart = lists:filter(fun (PartNode) ->
        maps:is_key(PartNode, NewSeen)
    end, Part),
    %
    % TODO: Should we update the partitions for all the ongoing steps?
    %
    ok = ?MODULE:sync_info(Name, Node, Known, Max, 1),
    _ = erlang:send_after(?PART_SYNC_INTERVAL, self(), sync_timer),
    NewState = State#state{
        seen = NewSeen,
        part = NewPart
    },
    {noreply, NewState};

handle_info({step_giveup, StepNum, StepRef}, State) ->
    NewState = step_do_giveup(StepNum, StepRef, State),
    {noreply, NewState};

handle_info({step_retry, StepNum, StepRef}, State) ->
    NewState = step_do_retry(StepNum, StepRef, State),
    {noreply, NewState};

handle_info({join_attempt_retry, PeerNode, Ref}, State) ->
    NewState = join_attempt_retry(PeerNode, Ref, State),
    {noreply, NewState};

handle_info({join_attempt, PeerNode, Ref}, State) ->
    NewState = join_attempt(PeerNode, Ref, State),
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
%%% Internal: Paxos API for updating the sequence.
%%% ============================================================================

%%  @doc
%%  Initialize new Paxos consensus for the next free element (step) of the sequence.
%%  Here the process acts as a proposer.
%%
step_do_initialize(Purpose, Timeout, State) ->
    #state{
        name  = Name,
        node  = Node,
        seen  = Seen,
        max   = Max,
        retry = Retry,
        steps = Steps
    } = State,
    StepRef   = erlang:make_ref(),
    StepNum   = lists:max([Max | maps:keys(Steps)]) + 1,
    Partition = maps:keys(Seen), % Try to agree across all the reachable nodes, not only the partition.
    Round     = {rand:uniform(), Node},
    ok = step_prepare(Name, StepNum, Partition, Round, Node),
    NewStep = #step{
        purpose     = Purpose,
        ref         = StepRef,
        giveup_time = erlang:system_time(millisecond) + Timeout,
        giveup_tref = erlang:send_after(Timeout, self(), {step_giveup, StepNum, StepRef}),
        retry_tref  = erlang:send_after(Retry,   self(), {step_retry,  StepNum, StepRef}),
        partition   = Partition,
        p_proposed  = {Round, Node}
    },
    State#state{
        steps = Steps#{StepNum => NewStep}
    }.


%%
%%  Gives up on the specified StepNum, and initializes the next one.
%%
step_do_next_attempt(StepNum, State = #state{steps = Steps}) ->
    #{StepNum := Step} = Steps,
    #step{
        purpose     = Purpose,
        giveup_time = GiveupTime
    } = Step,
    TmpState = State#state{
        steps = Steps#{StepNum => Step#step{purpose = undefined}}
    },
    NewTimeout = erlang:max(0, GiveupTime - erlang:system_time(millisecond)),
    step_do_initialize(Purpose, NewTimeout, TmpState).


%%  @private
%%  Retry is only initiated by the proposer, if the value was not yet chosen.
%%
step_do_retry(StepNum, StepRef, State = #state{name = Name, node = Node, retry = Retry, steps = Steps}) ->
    case Steps of
        #{StepNum := Step = #step{ref = StepRef, partition = Partition, p_proposed = {Round, _Value}, purpose = Purpose}} when Purpose =/= undefined ->
            ok = step_prepare(Name, StepNum, Partition, Round, Node),
            NewStep = Step#step{
                retry_tref = erlang:send_after(Retry, self(), {step_retry,  StepNum, StepRef})
            },
            State#state{
                steps = Steps#{StepNum => NewStep}
            };
        #{} ->
            State
    end.


%%  @private
%%  Close the particular step
%%
step_do_giveup(StepNum, StepRef, State = #state{steps = Steps}) ->
    case Steps of
        #{StepNum := Step = #step{ref = StepRef}} ->
            NewStep = Step#step{
                ref = timeout
            },
            step_do_cleanup(State#state{
                steps = Steps#{StepNum => NewStep}
            });
        #{} ->
            State
    end.


%%  @private
%%  Cleanup old steps, and update the min value accordingly.
%%
step_do_cleanup(State = #state{min = Min, steps = Steps}) ->
    CleanupFun = fun
        CleanupFun([StepNum | Other], AccMin, AccSteps) ->
            case AccSteps of
                #{StepNum := #step{ref = StepRef}} when StepRef =:= timeout; StepRef =:= chosen ->
                    % The lowest step is already timeouted, we can remove it.
                    CleanupFun(
                        Other,
                        erlang:max(AccMin, StepNum),
                        maps:remove(StepNum, AccSteps)
                    );
                #{StepNum := #step{}} ->
                    % Found first non-timeouted step, so we are done with the cleanup.
                    {AccMin, AccSteps}
            end;
        CleanupFun([], AccMin, AccSteps) ->
            {AccMin, AccSteps}
    end,
    {NewMin, NewSteps} = CleanupFun(lists:sort(maps:keys(Steps)), Min, Steps),
    State#state{
        min   = NewMin,
        steps = NewSteps
    }.


%%  @doc
%%  Paxos, phase 1, the `prepare' message.
%%  Sent from a proposer to all acceptors.
%%
step_prepare(Name, StepNum, Partition, Round, ProposerNode) ->
    abcast = gen_server:abcast(Partition, Name, {step_prepare, StepNum, Round, ProposerNode, Partition}),
    ok.


%%  @doc
%%  Paxos, phase 1, the `prepared' message.
%%  Sent from all the acceptors to a proposer.
%%
step_prepared(Name, StepNum, ProposerNode, Accepted, AcceptorNode, Partition) ->
    ok = gen_server:cast({Name, ProposerNode}, {step_prepared, StepNum, Accepted, AcceptorNode, Partition}).


%%  @doc
%%  Paxos, phase 2, the `accept!' message.
%%  Sent from a proposer to all acceptors.
%%
step_accept(Name, StepNum, Partition, Proposal) ->
    abcast = gen_server:abcast(Partition, Name, {step_accept, StepNum, Proposal, Partition}),
    ok.


%%  @doc
%%  Paxos, phase 2, the `accepted' message.
%%  Sent from from all acceptors to all the learners.
%%
step_accepted(Name, StepNum, Partition, Proposal, AcceptorNode) ->
    abcast = gen_server:abcast(Partition, Name, {step_accepted, StepNum, Proposal, AcceptorNode, Partition}),
    ok.



%%% ============================================================================
%%% Internal: Joining of nodes to the partition.
%%% ============================================================================

%%  @doc
%%  Returns a list of nodes, that are reachable (seen) but
%%  are not joined to our partition yet.
%%
join_pending(#state{seen = Seen, part = Part}) ->
    maps:keys(maps:without(Part, Seen)).


%%
%%
%%
join_start_if_needed(State = #state{joining = Joining}) ->
    Pending = join_pending(State),
    TmpJoining = maps:with(Pending, Joining),
    TmpState = State#state{
        joining = TmpJoining
    },
    lists:foldl(fun (Node, St) ->
        join_start(Node, St)
    end, TmpState, Pending -- maps:kes(Joining)).


%%
%%
%%
join_start(ThisNode, State = #state{node = ThisNode}) ->
    % Do not sync with self. Just in case.
    State;

join_start(PeerNode, State = #state{max = Max, steps = Steps, joining = Joining}) ->
    NewJoin = #join{
        node    = PeerNode,
        from    = 0,
        till    = lists:max([Max | maps:keys(Steps)]),
        dup_ids = []
    },
    NewState = State#state{
        joining = Joining#{PeerNode => NewJoin}
    },
    join_attempt_next(PeerNode, NewState).


%%
%%  Join attempt: Schedule the next attempt.
%%
join_attempt_next(PeerNode, State = #state{joining = Joining}) ->
    #{PeerNode := Join} = Joining,
    Ref = erlang:make_ref(),
    self() ! {join_attempt, PeerNode, Ref},
    timer:send_after(?DEFAULT_RETRY, self(), {join_attempt_retry, PeerNode, Ref}),
    State#state{
        joining = Joining#{PeerNode := Join#join{ref = Ref}}
    }.


%%
%%  Join attempt: Schedule a retry.
%%
join_attempt_retry(PeerNode, Ref, State = #state{joining = Joining}) ->
    case Joining of
        #{PeerNode := #join{ref = Ref}} -> join_attempt_next(PeerNode, State);
        #{                            } -> State % Drop the outdated message.
    end.


%%
%%  Join attempt: Perform single attempt.
%%
join_attempt(ThisNode, _Ref, State = #state{node = ThisNode}) ->
    % Do not sync with self. Just in case.
    State;

join_attempt(PeerNode, Ref, State = #state{name = Name, node = ThisNode, joining = Joining}) ->
    case Joining of
        #{PeerNode := Join = #join{ref = Ref, from = From, till = Till}} ->
            case join_completed(Join) of
                true ->
                    error_logger:info_msg("Joining ~p - completed.~n", [PeerNode]),
                    join_finalize(PeerNode, State);
                dup_ids ->
                    % Just wait for ids to be allocated.
                    error_logger:info_msg("Joining ~p - check completed, waiting for new ids to be allocated.~n", [PeerNode]),
                    State;
                checking ->
                    error_logger:info_msg("Joining ~p - check is ongoing.~n", [PeerNode]),
                    gen_server:cast({Name, PeerNode}, {join_sync_req, ThisNode, From, Till, ?MAX_JOIN_SYNC_SIZE}),
                    State
            end;
        #{} ->
            % Drop the outdated message.
            State
    end.


%%  @private
%%  This query can be implemented in some much more efficient way,
%%  maybe via callback, a database query, etc.
%%
join_sync_req(PeerNode, From, Till, MaxSize, State = #state{name = Name, node = ThisNode, ids = Ids}) ->
    SelectIds = fun SelectIds([Id | Other], Count, AccIds) ->
        if  Count =< 0 -> {hd(AccIds), lists:reverse(AccIds)};       % Overflow by size.
            Id > Till  -> {Till, lists:reverse(AccIds)};             % Range scanned.
            Id < From  -> SelectIds(Other, Count, AccIds);           % Skip the first ids.
            true       -> SelectIds(Other, Count - 1, [Id | AccIds]) % Collect them.
        end
    end,
    {ResIds, ResTill} = SelectIds(lists:usort(Ids), MaxSize, []),
    gen_server:cast({Name, PeerNode}, {join_sync_res, ThisNode, From, ResTill, ResIds}),
    State.


%%  @private
%%  Handle response to the `join_sync_req'.
%%
join_sync_res(PeerNode, From, Till, PeerIds, State = #state{max = Max, ids = Ids, steps = Steps, joining = Joining, dup_ids = DupIds}) ->
    %
    % Collect the duplicated ids (and ongoing steps).
    DuplicatedIds = lists:filter(fun (Id) ->
        lists:member(Id, Ids)
    end, PeerIds),
    DuplicatedSteps = lists:filter(fun (Id) ->
        case Steps of
            #{Id := #step{purpose = Purpose}} ->
                Purpose =/= undefined andalso not lists:member(Id, DuplicatedIds);
            #{} ->
                false
        end
    end, PeerIds),
    %
    % Allocate new IDs for those, that are duplicated.
    TmpStateDupIds = lists:foldl(fun (Id, AccState) ->
        case lists:member(Id, DupIds) of
            true  -> AccState; % Only start the allocation on the first detection.
            false -> step_do_initialize({join, Id}, ?DEFAULT_TIMEOUT, AccState)      % TODO: handle purpose.
        end
    end, State, DuplicatedIds),
    %
    % Retry allocation of steps, that will be duplicated.
    TmpStateDupSteps = lists:foldl(fun (Id, AccState) ->
        step_do_next_attempt(Id, AccState)
    end, TmpStateDupIds, DuplicatedSteps),
    %
    % Update the ranges and initiate the next step.
    case Joining of
        #{PeerNode := Join = #join{from = OurFrom, till = OurTill, dup_ids = OurJoinDupIds}} ->
            NewFrom = case (From =< OurFrom) andalso (OurFrom =< Till) of
                true  -> erlang:min(OurTill, Till);
                false -> OurFrom
            end,
            NewJoin = Join#join{
                from    = NewFrom,
                till    = lists:max([OurTill, Max | maps:keys(Steps)]),
                dup_ids = lists:usort(OurJoinDupIds, DuplicatedIds)
            },
            NewState = TmpStateDupSteps#state{
                joining = Joining#{PeerNode := NewJoin}
            },
            join_attempt_next(PeerNode, NewState);
        #{} ->
            TmpStateDupSteps
    end.


%%  @private
%%  New ID was chosen to replace a duplicated ID.
%%
join_sync_id_allocated(DupId, NewId, State = #state{map = Map, dup_ids = DupIds, joining = Joining}) ->
    TmpState = State#state{
        map     = Map#{DupId => NewId},
        dup_ids = lists:delete(DupId, DupIds)
    },
    lists:foldl(fun (PeerNode, AccState = #state{joining = AccJoining}) ->
        #{PeerNode := Join} = AccJoining,
        #join{dup_ids = JoinDupIds} = Join,
        NewJoinDupIds = lists:delete(DupId, JoinDupIds),
        NewJoin = Join#join{dup_ids = NewJoinDupIds},
        TmpAccState = AccState#state{joining = AccJoining#{PeerNode => NewJoin}},
        case NewJoinDupIds of
            []    -> join_attempt_next(PeerNode, TmpAccState);
            [_|_] -> TmpAccState
        end
    end, TmpState, maps:keys(Joining)).


%%
%%
%%
join_finalize(PeerNode, State = #state{part = Part, joining = Joining}) ->
    NewPart    = lists:usort([PeerNode | Part]),
    NewJoining = maps:remove(PeerNode, Joining),
    State#state{
        part    = NewPart,
        joining = NewJoining
    }.


%%  @doc
%%  Checks, if the join procedure is completed.
%%
join_completed(#join{from = From, till = Till, dup_ids = []}) when From >= Till -> true;
join_completed(#join{from = From, till = Till              }) when From >= Till -> dup_ids;
join_completed(#join{                                      })                   -> checking.



%%% ============================================================================
%%% Internal: Other.
%%% ============================================================================


