

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


<table width="100%" border="1" cellspacing="0" cellpadding="2" summary="function index"><tr><td valign="top"><a href="#describe-1">describe/1</a></td><td></td></tr><tr><td valign="top"><a href="#handle_check-2">handle_check/2</a></td><td>
Checks if provided list of IDs has numbers conflicting with this node.</td></tr><tr><td valign="top"><a href="#handle_new_id-2">handle_new_id/2</a></td><td></td></tr><tr><td valign="top"><a href="#handle_new_map-3">handle_new_map/3</a></td><td></td></tr><tr><td valign="top"><a href="#handle_new_max-2">handle_new_max/2</a></td><td></td></tr><tr><td valign="top"><a href="#handle_select-4">handle_select/4</a></td><td>
Returns a requested range of IDs owned by this node.</td></tr><tr><td valign="top"><a href="#init-1">init/1</a></td><td>
Initializes this callback.</td></tr></table>


<a name="functions"></a>

## Function Details ##

<a name="describe-1"></a>

### describe/1 ###

`describe(State) -> any()`

<a name="handle_check-2"></a>

### handle_check/2 ###

`handle_check(PeerIds, State) -> any()`

Checks if provided list of IDs has numbers conflicting with this node.

<a name="handle_new_id-2"></a>

### handle_new_id/2 ###

`handle_new_id(NewId, State) -> any()`

<a name="handle_new_map-3"></a>

### handle_new_map/3 ###

`handle_new_map(OldId, NewId, State) -> any()`

<a name="handle_new_max-2"></a>

### handle_new_max/2 ###

`handle_new_max(NewMax, State) -> any()`

<a name="handle_select-4"></a>

### handle_select/4 ###

`handle_select(From, Till, MaxCount, State) -> any()`

Returns a requested range of IDs owned by this node.

<a name="init-1"></a>

### init/1 ###

`init(Args) -> any()`

Initializes this callback.

