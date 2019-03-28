

# Paxoid -- Paxos based masterless sequence. #

This application implements a Paxos based masterless ID / Sequence generator.
It was built to assign short identifiers to the Erlang/OTP nodes in a cluster.
The assigned node identifiers then were used to generate object identifiers
of the form `{NodeId, LocalCounter}` locally.

The following are the main properties, that design was based on:

* The system should act in the AP mode (from the CAP theorem).
It is better to have sequence duplicated in the case of network
partitions instead of having system stalled. A merge procedure
is defined to repair partitions on merge by renumbering the
duplicated IDs.

* The system must preserve consistency in a single partition.
I.e. the AP choice should be no excuse for consistency, where
it can actually be achieved.

* The performance was not the primary concern, as the primary use
is expected to generate a small number of IDs, that are then
used by all the nodes as a prefixes for locally incrementing
counters.

* The ID should be small, to be able to display them in a GUI, etc.
We chosen it to be a number.

There are other techniques for generating (almost) unique IDs,
including GUIDs, Twitter's Snowflake, etc. Some overview can
be found at [Generating unique IDs in a distributed environment at high scale](https://www.callicoder.com/distributed-unique-id-sequence-number-generator/).
All of them are either non-masterless or have some probability
to generate duplicate IDs. Here we want to have defined semantics
for duplication of the IDs and recovery from that.


### <a name="Check_it_out">Check it out</a> ###

Start several nodes:

```
rebar3 shell --name a@127.0.0.1
rebar3 shell --name b@127.0.0.1
rebar3 shell --name c@127.0.0.1
```

Start a `paxoid` process on each node:

```
paxoid:start_link(test).
```

Then join them by running the following on any of the nodes:

```
paxoid:join(test, ['a@127.0.0.1', 'b@127.0.0.1', 'c@127.0.0.1']).
paxoid:info(test). % To get some details on the runtime.
```

Now you can call `paxoid:next_id(test)` to get new ID from the sequence
on any of the nodes.

In order to check, if ids can be retrieved in parallel, run the following
in each of the started nodes:

```
erlang:register(sh, self()),
receive start -> rp([paxoid:next_id(test) || _ <- lists:seq(1, 100)]) end.
```

and then start the parallel generation of ids by running the following
from a separate node (`rebar3 shell --name x@127.0.0.1`):

```
[ erlang:send({sh, N}, start) || N <- ['a@127.0.0.1', 'b@127.0.0.1', 'c@127.0.0.1']].
```


### <a name="Using_it_in_an_application">Using it in an application</a> ###

There are to ways to start the paxoid peers:

* _Supervised by the user application._ In this case one can get a supervisor's
    child specification by calling [`paxoid:start_spec/2`](paxoid.md#start_spec-2) and then pass
it to the corresponding application supervisor.
Most likely this is the preferred way.

* _Supervised by te `paxoid` application._ For this case one should call [`paxoid:start_sup/2`](paxoid.md#start_sup-2).
    The application can also use predefined paxoid peers. They can be configured
    via the `predefined` environment variable of the `paxoid` application.

The paxoid processes can be started with several options passed as a map with the following keys:

* `join => [node()]` -- a list of nodes we should synchronize with.
That's only an initial list, more nodes can be discovered later.
This can be used to join new node to an existing cluster.

* `callback => module() | {module(), Args :: term()}` -- a callback
    module implementing the [`paxoid`](paxoid.md) behaviour. It can be used to
    implement a custom persistence as well as to get notifications
    on various events (like new mapping for a duplicated ID).
    You can look at [`paxoid_cb_mem`](paxoid_cb_mem.md) for an example of such
a callback module. This module is used by default.


### <a name="Design_choices">Design choices</a> ###

* Sequences are named using `atom`s only. This allows to register peers
    using the local registry and to access them via `{Name, Node}`.
    We wanted to avoid additional dependencies. Maybe `pg2` can be used instead.
The atoms were considered as good enough for naming, because the distributed
sequence is designed to be used as a basis for local counters, thus number of
sequences will be low.

* Single peer is implemented as a single process. This process combines several
    FSMs (startup phases, a list of consensus attempts, a list of merge attempts),
    although they are sharing a lot of common state. Splitting them to separate
    processes could increase the complexity by adding the coordination between them.
    Another reason here is related to the process registry. If we are not using
    a registry like `gproc`, we need to maintain the relations between processes,
thus again adding additional complexity.


### <a name="Formal_verification">Formal verification</a> ###

TBD: TLA+ specification.


## Modules ##


<table width="100%" border="0" summary="list of modules">
<tr><td><a href="paxoid.md" class="module">paxoid</a></td></tr>
<tr><td><a href="paxoid_cb_file.md" class="module">paxoid_cb_file</a></td></tr>
<tr><td><a href="paxoid_cb_mem.md" class="module">paxoid_cb_mem</a></td></tr></table>

