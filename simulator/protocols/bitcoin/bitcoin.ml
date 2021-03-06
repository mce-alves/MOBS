open Implementation

module BlockContents = struct
  type t = unit
end

type msg = 
  Block of BlockContents.t Simulator.Block.t (* block *)
  | Inv of int*int           (* blockID, from *)
  | Rec of int*int           (* blockID, from *)

module BitcoinMsg : (Simulator.Events.Message with type t = msg) = struct 
  type t = msg

  let to_json (msg:t) : string =
    match msg with
    | Block(b)  -> Printf.sprintf "{\"type\":\"BLOCK\",\"block_id\":\"%d\"}" (Simulator.Block.id b)
    | Inv(id,_) -> Printf.sprintf "{\"type\":\"INV\",\"block_id\":\"%d\"}" id
    | Rec(id,_) -> Printf.sprintf "{\"type\":\"REC\",\"block_id\":\"%d\"}" id

  let get_size (msg:t) =
    match msg with
    | Block(_) -> Simulator.Size.Kilobyte(534)
    | Inv(_,_) -> Simulator.Size.Bit(32)
    | Rec(_,_) -> Simulator.Size.Bit(32)

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
module BitcoinTimer   = Abstractions.Timer.Make(BitcoinEvent)(BitcoinQueue);;
module BitcoinBlock   = Simulator.Block.Make(BitcoinLogger)(BlockContents)(Simulator.Block.BaseRewards);;
module BitcoinPow     = Abstractions.Pow.Make(BitcoinEvent)(BitcoinQueue)(BitcoinBlock);;
let _ = BitcoinPow.init_mining_power ();;


module MBPTimeArg = struct
  let label = "median-block-propagation-time"
  let use_intervals = false
  let format = 1
end

module BitcoinStatistics = Simulator.Statistics.Make.Median(MBPTimeArg);;


module BitcoinNode : (Protocol.BlockchainNode with type ev=BitcoinEvent.t and type value=BitcoinBlock.block) = struct
  
  type value = BitcoinBlock.block

  module V = struct
    type v = value
  end

  include Protocol.MakeBaseNode(V)

  type ev = BitcoinEvent.t

  type node_data = {
    mutable received_blocks : BitcoinBlock.block list;
    mutable downloading_blocks : int list;
    mutable sending : bool;
  }

  type t = (node_data, value) Protocol.template

  let init id links region : (t) =
    {
      id = id;
      region = region;
      links = links;
      state = BitcoinBlock.null ();
      data  = {
        received_blocks = [];
        downloading_blocks = [];
        sending = false;
      }
    }
  
  let send_to_neighbours (node:t) msg =
    Array.iter (fun neighbour -> BitcoinNetwork.send node.id neighbour msg) node.links

  let add_to_chain (node:t) block =
    node.state <- block

  let get_block (node:t) bid =
    let b = ref None in
    List.iter (fun blk -> if BitcoinBlock.id blk = bid then b := Some blk) node.data.received_blocks;
    !b

  let process_block (node:t) block =
    let is_valid_block b = 
      if node.state = BitcoinBlock.null () then
        true
      else 
        begin
          if BitcoinBlock.total_difficulty b > BitcoinBlock.total_difficulty node.state then true else false
        end
    in
    let already_seen = (List.exists (fun x -> BitcoinBlock.id x=(BitcoinBlock.id block)) node.data.received_blocks) in
    if is_valid_block block && not already_seen then begin
      add_to_chain node block;
      let delay = (Simulator.Clock.get_timestamp ()) - (BitcoinBlock.timestamp block) in
      BitcoinStatistics.process node.id delay;
      node.data.received_blocks <- node.data.received_blocks @ [block];
      send_to_neighbours node (Inv(BitcoinBlock.id block, node.id));
      (* TODO : remove block from "downloading" list *)
      BitcoinPow.stop_minting node.id;
      BitcoinPow.start_minting node.id block;
    end;
    node

  let process_inv (node:t) bid sender = 
    let already_received = List.exists (fun x -> BitcoinBlock.id x = bid) node.data.received_blocks in
    let downloading = List.exists (fun x -> x = bid) node.data.downloading_blocks in
    if not downloading && not already_received then
      begin
        BitcoinNetwork.send node.id sender (Rec(bid,node.id));
        node.data.downloading_blocks <- node.data.downloading_blocks@[bid];
        node
      end
    else
      node

  let process_rec (node:t) bid sender = 
    let blk = get_block node bid in
    match blk with
    | Some(b) -> 
      BitcoinNetwork.send node.id sender (Block(b)); node
    | None -> node

  let handle (node:t) (event:ev) : t =
    match event with
    | BitcoinEvent.MintBlock(_,_) ->
      begin
        if node.state = BitcoinBlock.null () then
          process_block node (BitcoinBlock.genesis_pow node.id (BitcoinPow.total_mining_power ()) ()) 
        else
          process_block node (BitcoinBlock.create node.id node.state ())
      end
    | BitcoinEvent.Message(_,_,_,_,msg) -> 
      begin
      match msg with
      | Block(b) -> process_block node b
      | Inv(id,sender)  -> process_inv node id sender
      | Rec(id,sender)  -> process_rec node id sender
      end
    | _ -> node

  (* this function is the same in every blockchain-specific node, 
    just changing the prefix of the protocol (AlgorandBlock, BitcoinBlock, SimpleBlock, _Block...) *)
  let chain_height (node:t) = 
    BitcoinBlock.height node.state


end

module BitcoinInitializer : (Protocol.Initializer with type node=BitcoinNode.t and type ev=BitcoinEvent.t) = struct
  type node = BitcoinNode.t

  type ev = BitcoinEvent.t

  let init nodes = 
    let index = (Random.int ((Hashtbl.length nodes)-1))+1 in
    [BitcoinEvent.MintBlock(index, 0)]
  
end

module BitcoinProtocol = Protocol.Make.Blockchain(BitcoinEvent)(BitcoinQueue)(BitcoinBlock)(BitcoinTimer)(BitcoinNode)(BitcoinNode)(BitcoinInitializer)(BitcoinLogger)(BitcoinStatistics)(BitcoinNetwork);;










