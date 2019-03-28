

# Module paxoid_cb_file #
* [Description](#description)
* [Function Index](#index)
* [Function Details](#functions)

Callback module for `paxoid`, storing all the state in a file.

__Behaviours:__ [`paxoid`](paxoid.md).

<a name="description"></a>

## Description ##
The file is the plain-text one, used with `file:consult/*`.
Most likely you will use this module as an example on how
to implement own callback with persistence.
<a name="index"></a>

## Function Index ##


<table width="100%" border="1" cellspacing="0" cellpadding="2" summary="function index"><tr><td valign="top"><a href="#describe-1">describe/1</a></td><td>
Return IDs owned by this node.</td></tr><tr><td valign="top"><a href="#handle_changed_cluster-3">handle_changed_cluster/3</a></td><td>
This function is called, when new nodes are added/discovered in the cluster.</td></tr><tr><td valign="top"><a href="#handle_changed_partition-3">handle_changed_partition/3</a></td><td>
This function is called when our view of the partition has changed.</td></tr><tr><td valign="top"><a href="#handle_check-2">handle_check/2</a></td><td>
Checks if provided list of IDs has numbers conflicting with this node.</td></tr><tr><td valign="top"><a href="#handle_new_id-2">handle_new_id/2</a></td><td>
Stores new ID allocated to this node, and upates known maximum, if needed.</td></tr><tr><td valign="top"><a href="#handle_new_map-3">handle_new_map/3</a></td><td>
Replaces duplicated ID with new one, and upates known maximum, if needed.</td></tr><tr><td valign="top"><a href="#handle_new_max-2">handle_new_max/2</a></td><td>
Updates maximal known ID in the scope of the entire cluster.</td></tr><tr><td valign="top"><a href="#handle_select-4">handle_select/4</a></td><td>
Returns a requested range of IDs owned by this node.</td></tr><tr><td valign="top"><a href="#init-3">init/3</a></td><td>
Initializes this callback.</td></tr></table>


<a name="functions"></a>

## Function Details ##

<a name="describe-1"></a>

### describe/1 ###

`describe(State) -> any()`

Return IDs owned by this node.

<a name="handle_changed_cluster-3"></a>

### handle_changed_cluster/3 ###

`handle_changed_cluster(OldNodes, NewNodes, State) -> any()`

This function is called, when new nodes are added/discovered in the cluster.
They can be unreachable yet, but already known.

We will save them to a file to read them again on startup.

<a name="handle_changed_partition-3"></a>

### handle_changed_partition/3 ###

`handle_changed_partition(OldNodes, NewNodes, State) -> any()`

This function is called when our view of the partition has changed.

We do nothing in this case.

<a name="handle_check-2"></a>

### handle_check/2 ###

`handle_check(PeerIds, State) -> any()`

Checks if provided list of IDs has numbers conflicting with this node.

<a name="handle_new_id-2"></a>

### handle_new_id/2 ###

`handle_new_id(NewId, State) -> any()`

Stores new ID allocated to this node, and upates known maximum, if needed.

<a name="handle_new_map-3"></a>

### handle_new_map/3 ###

`handle_new_map(OldId, NewId, State) -> any()`

Replaces duplicated ID with new one, and upates known maximum, if needed.

<a name="handle_new_max-2"></a>

### handle_new_max/2 ###

`handle_new_max(NewMax, State) -> any()`

Updates maximal known ID in the scope of the entire cluster.

<a name="handle_select-4"></a>

### handle_select/4 ###

`handle_select(From, Till, MaxCount, State) -> any()`

Returns a requested range of IDs owned by this node.

<a name="init-3"></a>

### init/3 ###

`init(Name, Node, Args) -> any()`

Initializes this callback.

Tries to read all the relevant info from a file.

