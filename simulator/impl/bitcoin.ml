type msg = 
  Block of Simulator.Block.t (* block *)
  | Inv of int*int           (* blockID, from *)
  | Rec of int*int           (* blockID, from *)

module BitcoinMsg : (Simulator.Events.Message with type t = msg) = struct 
  type t = msg

  let to_json (msg:t) : string =
    match msg with
    | Block(b)  -> String.concat "" ["{\"type\":\"BLOCK\",\"block_id\":\"";string_of_int (Simulator.Block.id b);"\"}"]
    | Inv(id,_) -> String.concat "" ["{\"type\":\"INV\",\"block_id\":\"";string_of_int id;"\"}"]
    | Rec(id,_) -> String.concat "" ["{\"type\":\"REC\",\"block_id\":\"";string_of_int id;"\"}"]

  let get_size (msg:t) =
    match msg with
    | Block(_) -> 4280000
    | Inv(_,_) -> 32
    | Rec(_,_) -> 32

  let processing_time (_:t) =
    2

  let identifier (msg:t) =
    match msg with
    | Block(b) -> Simulator.Block.id b
    | Inv(id,_)  -> id
    | Rec(id,_)  -> id

end

module BitcoinEvent   = Simulator.Events.MakeEvent(BitcoinMsg);;
module BitcoinQueue   = Simulator.Events.MakeQueue(BitcoinEvent);;
module BitcoinNetwork = Abstractions.Network.Make(BitcoinEvent)(BitcoinQueue)(BitcoinMsg);;
module BitcoinLogger  = Simulator.Logging.Make(BitcoinMsg)(BitcoinEvent);;
module BitcoinBlock   = Simulator.Block.Make(BitcoinLogger);;
module BitcoinPow     = Abstractions.Pow.Make(BitcoinEvent)(BitcoinQueue)(BitcoinBlock);;
let _ = BitcoinPow.init_mining_power ();;

module BitcoinStatistics = struct

  type ev = BitcoinEvent.t
  type value = Simulator.Block.t

  (* Observed Delay per Block per Node *)
  let odpb = ref []

  let received_new_block blk =
    let delay = (Simulator.Clock.get_timestamp ()) - (BitcoinBlock.timestamp blk) in
    let blkID = BitcoinBlock.id blk in
    let found = ref false in
    odpb := List.map (
      fun (id,delays) -> 
        if blkID = id then
          begin
            found := true;
            (id, delays@[delay])
          end
        else
          (id,delays)
      ) !odpb;
    if not !found then odpb := !odpb@[(blkID,[delay])]

  let consensus_reached _ _ =
    ()

  let process _ =
    ()

  let get () =
    if List.length !odpb > 0 then
      let sum = ref 0 in
      let odpb_50 = ref [] in
      let max_odpb = List.map(
        fun (_,delays) ->
          let sorted_delays = List.sort compare delays in
          let max = List.nth sorted_delays (List.length sorted_delays -1) in
          let reach50 = List.nth sorted_delays ((List.length sorted_delays)/2) in
          odpb_50 := !odpb_50@[reach50];
          sum := !sum + max;
          max
        ) !odpb in
      let avg_bpt = !sum / (List.length max_odpb) in
      let sorted_odpb_50 = List.sort compare !odpb_50 in
      let median_bpt = List.nth sorted_odpb_50 ((List.length sorted_odpb_50)/2) in
      print_endline "";
      print_string "MEDIAN(reach half of nodes): ";
      print_endline (string_of_int median_bpt);
      print_string "AVG(reach all nodes): ";
      print_endline (string_of_int avg_bpt);
      String.concat "" ["{\"average-block-propagation-time\":";string_of_int avg_bpt;",\"median-block-propagation-time\":";string_of_int median_bpt;"}"]
    else
      "{}"

end


module BitcoinNode : (Protocol.Node with type ev=BitcoinEvent.t and type value=Simulator.Block.t) = struct
  
  type value = Simulator.Block.t

  module V = struct
    type v = value
  end

  module Unique:(Simulator.Unique.Unique with type v = V.v) = Simulator.Unique.Make(V)

  type ev = BitcoinEvent.t

  type t = {
    id     : int;
    region : Abstractions.Network.region;
    links  : Abstractions.Network.links;
    mutable state: value;
    mutable received_blocks : Simulator.Block.t list;
    mutable downloading_blocks : int list;
    mutable outgoing_queue : (msg * int) list;
    mutable sending : bool;
  }

  let init id links region =
    {
      id = id;
      region = region;
      links = links;
      state = BitcoinBlock.null;
      received_blocks = [];
      downloading_blocks = [];
      outgoing_queue = [];
      sending = false;
    }
  
  let send_to_neighbours node msg =
    List.iter (fun neighbour -> BitcoinNetwork.send node.id neighbour msg) node.links

  let add_to_chain node block =
    node.state <- block

  let get_block node bid =
    let b = ref None in
    List.iter (fun blk -> if BitcoinBlock.id blk = bid then b := Some blk) node.received_blocks;
    !b

  let process_block node block =
    let is_valid_block b = 
      if node.state = BitcoinBlock.null then
        true
      else 
        begin
          if BitcoinBlock.total_difficulty b > BitcoinBlock.total_difficulty node.state then true else false
        end
    in
    let already_seen = (List.exists (fun x -> BitcoinBlock.id x=(BitcoinBlock.id block)) node.received_blocks) in
    if is_valid_block block && not already_seen then begin
      add_to_chain node block;
      BitcoinStatistics.received_new_block block;
      node.received_blocks <- node.received_blocks @ [block];
      send_to_neighbours node (Inv(BitcoinBlock.id block, node.id));
      (* TODO : remove block from "downloading" list *)
      BitcoinPow.stop_minting node.id;
      BitcoinPow.start_minting node.id block;
    end;
    node

  let process_inv node bid sender = 
    let already_received = List.exists (fun x -> BitcoinBlock.id x = bid) node.received_blocks in
    let downloading = List.exists (fun x -> x = bid) node.downloading_blocks in
    if not downloading && not already_received then
      begin
        BitcoinNetwork.send node.id sender (Rec(bid,node.id));
        node.downloading_blocks <- node.downloading_blocks@[bid];
        node
      end
    else
      node

  let send_next_block node =
    match node.outgoing_queue with
    | []    ->
      node.sending <- false;
      node
    | (msg,target)::xs -> 
      BitcoinNetwork.send node.id target msg;
      node.outgoing_queue <- xs;
      node.sending <- true;
      node

  let process_rec node bid sender = 
    let blk = get_block node bid in
    match blk with
    | Some(b) -> 
      node.outgoing_queue <- node.outgoing_queue@[(Block(b), sender)];
      if not node.sending then send_next_block node else node
    | None -> node

  let handle (node:t) (event:ev) : t =
    match event with
    | BitcoinEvent.MintBlock(_,_) ->
      begin
        if node.state = BitcoinBlock.null then
          process_block node (BitcoinBlock.genesis_pow node.id (BitcoinPow.total_mining_power ())) 
        else
          process_block node (BitcoinBlock.create node.id node.state)
      end
    | BitcoinEvent.Message(_,_,_,msg) -> 
      begin
      match msg with
      | Block(b) -> process_block node b
      | Inv(id,sender)  -> process_inv node id sender
      | Rec(id,sender)  -> process_rec node id sender
      end
    | BitcoinEvent.Timeout(_,_,"message_sent") -> send_next_block node
    | _ -> node

  (* this function is the same in every blockchain node, 
    just changing the prefix of the protocol (AlgorandBlock, BitcoinBlock, SimpleBlock, _Block...) *)
  let chain_height node = 
    BitcoinBlock.height node.state

  (* The following four functions are the same for every node object *)
  let compare n1 n2 =
    if n1.id < n2.id then -1 else if n1.id > n2.id then 1 else 0
  
  let state n =
    n.state

  let state_id n =
    Unique.id n.state

  let parameters () =
    Parameters.Protocol.get ()

end

module BitcoinInitializer : (Abstract.Initializer with type node=BitcoinNode.t and type ev=BitcoinEvent.t) = struct
  type node = BitcoinNode.t

  type ev = BitcoinEvent.t

  let init nodes = 
    let index = (Random.int ((Hashtbl.length nodes)-1))+1 in
    [BitcoinEvent.MintBlock(index, 0)]
  
end

module BitcoinProtocol = Protocol.Make(BitcoinEvent)(BitcoinQueue)(BitcoinBlock)(BitcoinNode)(BitcoinInitializer)(BitcoinLogger)(BitcoinStatistics);;










