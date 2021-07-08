# Simulator



## Implementing a Protocol

The [protocol.ml](/simulator/impl/protocol.ml) file contains the signature of the modules that a user needs to implement. 


First, the user must implement a module ```Message``` containing the ```type``` of the messages that will be exchanged in the network, as well as some required operations.


```
module type Message = sig
  (** the type of a message *)
  type t

  (** convert a message to JSON string *)
  val to_json : t -> string

  (** returns the size of a message, in bits *)
  val get_size : t -> int

  (** returns the amount of time required to process a message, in millisseconds *)
  val processing_time : t -> int

  (** given a message, produce an integer that identifies the content of the message *)
  val identifier : t -> int

end
```

Then, the implementation of a ```Node``` module is required. It encompasses the type of the node and some required operations, with the ```handle``` function being the most important one as it receives the current state of a node and an event, and returns the new state of the node after processing that event.

```
module type Node = sig
  type block

  (** the id of a node *)
  type id = int

  (** the type of the events being handled *)
  type ev

  (** the type representing a node and its state *)
  type t

  (** create the initial state of a node *)
  val init : id -> Abstractions.Network.links -> Abstractions.Network.region -> t

  (** receives the state of a node and an event, returning the resulting state *)
  val handle : t -> ev -> t

  (** compares two nodes *)
  val compare : t -> t -> int

  (** obtain the height of the chain stored in the node *)
  val chain_height : t -> int

  (** get the head of the chain *)
  val chain_head : t -> block option

  (** return a JSON string containing the parameters (and values) of the protocol, if any *)
  val parameters : unit -> string

end
```

Next, the user must provide an implementation for an ```Initializer```, which contains one function that receives the nodes and their states, and must return the list of events that kickstart the entire simulation. For example, in Algorand that list of events will be setting the timers for each node, whereas in a PoW protocol it can be selecting a random node to mint the genesis block.

```
module type Initializer = sig
  (** the type representing a node *)
  type node

  (** the type of the events being produced *)
  type ev

  (** returns a list of events that kickstart the simulation *)
  val init : (int, node) Hashtbl.t -> ev list
end
```

A user can the implement a ```Statistics``` module. The purpose of this module is to produce user-defined metrics about the execution of the protocol such as: number of messages exchanged, number of forks, block propagation time, average time to reach consensus, etc. These metrics will then be displayed in the [GUI](/visualizer).

```
module type Statistics = sig

  (** the type representing events in the simulator *)
  type ev

  (** receives an event and processes it, updating statistics *)
  val process : ev -> unit

  (** returns a JSON string containing the statistics and respective values *)
  val get : unit -> string

  (** node has seen consensus for a block *)
  val consensus_reached : int -> Simulator.Block.t -> unit

end
```

Finally, a user calls a series of *functors* passing as parameters the implemented modules, in order to obtain all the modules required by the *protocol functor*:

```
module ImplEvent   = Simulator.Events.MakeEvent(ImplMsg);;
module ImplQueue   = Simulator.Events.MakeQueue(ImplEvent);;
module ImplNetwork = Abstractions.Network.Make(ImplEvent)(ImplQueue)(ImplMsg);;
module ImplLogger  = Simulator.Logging.Make(ImplMsg)(ImplEvent);;
module ImplBlock   = Simulator.Block.Make(ImplLogger);;
module ImplPow     = Abstractions.Pow.Make(ImplEvent)(ImplQueue)(ImplBlock);;

module ImplProtocol = Protocol.Make(ImplEvent)(ImplQueue)(ImplBlock)(ImplNode)
                                   (ImplInitializer)(ImplLogger)(ImplStatistics);;
```

For now, a user must change [main.ml](/simulator/bin/main.ml) to use the newly implemented protocol. We plan on adding the ability to select the protocol via the [GUI](/visualizer).

Examples:

- [SimplePoW](/simulator/impl/simplePoW.ml) contains a very simple example of how to implement a protocol in the simulator. 

- [Bitcoin](/simulator/impl/bitcoin.ml) contains an implementation of the Bitcoin protocol. It is a more detailed example than ```SimplePoW```, taking advantage of some more abstractions provided by the simulator.

- [Algorand](/simulator/impl/algorand.ml) contains an implementation of the Algorand Agreement protocol, with some simplifications, as an example for a Proof of Stake protocol.


## Simulator Abstractions


The [abstractions directory](/simulator/abstractions) contains abstractions for some common operations used in these protocols:

- ```network``` - contains abstractions for sending messages between nodes. It is important to note that, since blocks don't have negligible size, every time a block is successfully sent by a node, that node receives a ```timeout``` event with label ```"message_sent"```. A user can choose to ignore this event, but it plays an important role when we want to model that a node cannot use its entire bandwidth for each block being sent, when sending multiple blocks to its neighbors. An example of the usage of this event can be seen in [bitcoin.ml](/simulator/impl/bitcoin.ml).
- ```pow``` - defines an abstraction to begin and to stop minting. Essentially uses the hashing power of a node and the difficulty of a block to make an estimate of how long it takes to find the hash, and adds that event to the queue. If the node stops minting before the event is processed, it will get removed from the event queue.
- ```pos``` - contains an abstraction for committee selection based on stakes. Using these abstractions lead to the role of a node to be displayed in the [GUI](/visualizer).
- ```timer``` - contains an abstraction for scheduling a ```timeout``` event for a node.


## Simulator Parameterization


The simulator can be parametrized via ```json```, by changing ```default-parameters.json```. More information on how to use the parameters and change them can be found [here](/visualizer/README.md).