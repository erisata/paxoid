

# Module paxoid #
* [Description](#description)
* [Data Types](#types)
* [Function Index](#index)
* [Function Details](#functions)

The Paxos based distributed masterless sequence.

__Behaviours:__ [`gen_server`](gen_server.md).

__This module defines the `paxoid` behaviour.__<br /> Required callback functions: `init/3`, `describe/1`, `handle_new_id/2`, `handle_new_map/3`, `handle_new_max/2`, `handle_changed_cluster/3`, `handle_changed_partition/3`, `handle_select/4`, `handle_check/2`.

<a name="description"></a>

## Description ##

<a name="types"></a>

## Data Types ##




### <a name="type-num">num()</a> ###


<pre><code>
num() = pos_integer()
</code></pre>




### <a name="type-opts">opts()</a> ###


<pre><code>
opts() = #{join =&gt; [node()], callback =&gt; module() | {module(), Args::term()}}
</code></pre>

<a name="index"></a>

## Function Index ##


<table width="100%" border="1" cellspacing="0" cellpadding="2" summary="function index"><tr><td valign="top"><a href="#info-1">info/1</a></td><td>
Returns descriptive information about this node / process.</td></tr><tr><td valign="top"><a href="#join-2">join/2</a></td><td>
Add nodes to a list of known nodes to synchronize with.</td></tr><tr><td valign="top"><a href="#next_id-1">next_id/1</a></td><td>Equivalent to <a href="#next_id-2"><tt>next_id(Name, 5000)</tt></a>.</td></tr><tr><td valign="top"><a href="#next_id-2">next_id/2</a></td><td>
Returns next number from the sequence.</td></tr><tr><td valign="top"><a href="#start-0">start/0</a></td><td>
A convenience function allowing to start <code>Paxoid</code> from the command line (<code>erl -s paxoid</code>).</td></tr><tr><td valign="top"><a href="#start-1">start/1</a></td><td>
Start this node even if no peers can be discovered.</td></tr><tr><td valign="top"><a href="#start_link-1">start_link/1</a></td><td>Equivalent to <a href="#start_link-2"><tt>start_link(Name, #{})</tt></a>.</td></tr><tr><td valign="top"><a href="#start_link-2">start_link/2</a></td><td>
Start a paxoid process/node.</td></tr><tr><td valign="top"><a href="#start_spec-1">start_spec/1</a></td><td>Equivalent to <a href="#start_spec-2"><tt>start_spec(Name, #{})</tt></a>.</td></tr><tr><td valign="top"><a href="#start_spec-2">start_spec/2</a></td><td>
Produces a supervisor's child specification for starting
this process.</td></tr><tr><td valign="top"><a href="#start_sup-1">start_sup/1</a></td><td>Equivalent to <a href="#start_sup-2"><tt>start_sup(Name, #{})</tt></a>.</td></tr><tr><td valign="top"><a href="#start_sup-2">start_sup/2</a></td><td>
Start a paxoid process supervised by the paxoid instead of user application.</td></tr></table>


<a name="functions"></a>

## Function Details ##

<a name="info-1"></a>

### info/1 ###

`info(Name) -> any()`

Returns descriptive information about this node / process.

<a name="join-2"></a>

### join/2 ###

`join(Name, Node) -> any()`

Add nodes to a list of known nodes to synchronize with.

<a name="next_id-1"></a>

### next_id/1 ###

`next_id(Name) -> any()`

Equivalent to [`next_id(Name, 5000)`](#next_id-2).

<a name="next_id-2"></a>

### next_id/2 ###

`next_id(Name, Timeout) -> any()`

Returns next number from the sequence.

<a name="start-0"></a>

### start/0 ###

`start() -> any()`

A convenience function allowing to start `Paxoid` from the command line (`erl -s paxoid`).

<a name="start-1"></a>

### start/1 ###

`start(Name) -> any()`

Start this node even if no peers can be discovered.

<a name="start_link-1"></a>

### start_link/1 ###

`start_link(Name) -> any()`

Equivalent to [`start_link(Name, #{})`](#start_link-2).

<a name="start_link-2"></a>

### start_link/2 ###

<pre><code>
start_link(Name::atom(), Opts::<a href="#type-opts">opts()</a>) -&gt; {ok, pid()} | {error, Reason::term()}
</code></pre>
<br />

Start a paxoid process/node.

<a name="start_spec-1"></a>

### start_spec/1 ###

`start_spec(Name) -> any()`

Equivalent to [`start_spec(Name, #{})`](#start_spec-2).

<a name="start_spec-2"></a>

### start_spec/2 ###

`start_spec(Name, Opts) -> any()`

Produces a supervisor's child specification for starting
this process.

<a name="start_sup-1"></a>

### start_sup/1 ###

`start_sup(Name) -> any()`

Equivalent to [`start_sup(Name, #{})`](#start_sup-2).

<a name="start_sup-2"></a>

### start_sup/2 ###

`start_sup(Name, Opts) -> any()`

Start a paxoid process supervised by the paxoid instead of user application.

