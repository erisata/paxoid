# PaxoID #

This application implements a Paxos based masterless ID / Sequence generator.
The folloing are the main properties, that design was based on:

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

There are other techniques for generating almost unique ids,
including GUIDs, Twitter's Snowflake, etc. Some overview can
be found at [Generating unique IDs in a distributed environment at high scale](https://www.callicoder.com/distributed-unique-id-sequence-number-generator/).
All of them are either non-masterless or have some probability
to generate duplicate IDs. Here we want to have defined semantics
for duplication of the IDs and recovery from that.

## Check it out ##

Start several nodes:


    rebar3 shell --name a@127.0.0.1
    rebar3 shell --name b@127.0.0.1
    rebar3 shell --name c@127.0.0.1

Start a paxoid process on each node:

    paxoid:start_link(test).

Then join them by running the following on any of the nodes:

    paxoid:join(test, ['a@127.0.0.1', 'b@127.0.0.1', 'c@127.0.0.1']).
    paxoid:info(test). % To get some details on the runtime.

Now you can call `paxoid:next_id(test)` to get new ID from the sequence
on any of the nodes.

In order to check, if ids can be retrieved in parallel, run the following
in each of the started nodes:

    erlang:register(sh, self()),
    receive start -> rp([paxoid:next_id(test) || _ <- lists:seq(1, 100)]) end.

and then start the parallel generation of ids by starting a separate node:

    rebar3 shell --name x@127.0.0.1
        [ erlang:send({sh, N}, start) || N <- ['a@127.0.0.1', 'b@127.0.0.1', 'c@127.0.0.1']].


## Using it in an application ##

