(** Abstraction for common operations in proof of work protocols. *)
module type PoW = sig

  (** Initialize the mining power of the nodes according to the parameters *)
  val init_mining_power : unit -> unit

  (** Given a node's ID and a block, starts the minting process by nodeID to extend that block
    @param node_id the id of the node begining the minting process
    @param block the head of the chain to be extended
  *)
  val start_minting : int -> 'a Simulator.Block.t -> unit

  (** Given a node's ID, stops its minting process
    @param node_id the id of the node stopping the minting process
  *)
  val stop_minting : int -> unit

  (** Get the mining power of a given node.
    @param node_id the id of the node
  *)
  val get_mining_power : int -> int

  (** Get the network's total mining power. *)
  val total_mining_power : unit -> int
end

(** Creates an implementation for PoW, given the Event and EventQueue modules. *)
module Make(Events : Simulator.Events.Event)(Queue : Simulator.Events.EventQueue with type ev = Events.t)(Block : Simulator.Block.BlockSig) : PoW = struct

  let mining_power : int list ref = ref []

  let init_mining_power () =
    let num_nodes = !Parameters.General.num_nodes in
    if !Parameters.General.use_topology_file then
      (
        let open Yojson.Basic.Util in
        let node_data = Parameters.General.parse_topology_file !Parameters.General.topology_filename in
        List.iter (
          fun node ->
            let hPower   = node |> member "hPower" |> to_int in
            mining_power := !mining_power@[hPower];
        ) node_data
      )
    else (
      for _ = 0 to num_nodes do 
        let r = Random.float 1. in
        let b = Random.bool () in
        let power = 
          match b with
          | true  -> int_of_float (float_of_int(!Parameters.General.avg_mining_power) +. (r *. float_of_int(!Parameters.General.stdev_mining_power)))
          | false -> int_of_float (float_of_int(!Parameters.General.avg_mining_power) -. (r *. float_of_int(!Parameters.General.stdev_mining_power)))
        in
        mining_power := !mining_power @ [max power 1]
      done
    )

  let get_mining_power nodeID =
    List.nth !mining_power (nodeID)

  let total_mining_power () =
    let rec sum l =
      match l with
      | [] -> 0
      | x::xs -> x + sum xs
    in
    sum !mining_power

  let start_minting nodeID parent =
    let difficulty = Block.difficulty parent in
    let p = 1. /. (float_of_int difficulty) in
    let u = Random.float 1. in
    let mining_power = float_of_int(get_mining_power nodeID) in
    let mint_duration = int_of_float((log(u) /. log(1. -. p)) /. mining_power) in
    let mint_conclusion = (Simulator.Clock.get_timestamp ()) + mint_duration in
    let mint_event = Events.create_mint nodeID mint_conclusion in
    if p > (2. ** -53.) then Queue.add_event mint_event

  let stop_minting nodeID =
    Queue.cancel_minting nodeID

end