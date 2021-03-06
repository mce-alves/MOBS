type links         = int array
type network_links = links array
type region        = int
type regions       = int array 

(*******************************)

module type Network = sig
  type msg

  module MessagesExchanged : Simulator.Statistics.Stats
  module MegabytesExchanged : Simulator.Statistics.Stats

  val send : int -> int -> msg -> unit

  val send_to_neighbors : int -> msg -> unit

  val gossip : int -> msg -> unit

  val get_neighbours : int -> links

  val clear : unit -> unit

  val get_links : unit -> network_links

  val get_regions : unit -> regions
end

module Make(Events: Simulator.Events.Event) 
          (Queue: Simulator.Events.EventQueue with type ev = Events.t)
          (Message : Simulator.Events.Message with type t = Events.msg) : (Network with type msg=Events.msg) =
struct

  (*** Hidden Operations ***)

  (* shuffle an array by tagging each element with random bits, and then using the sort function *)
  (* the usage of the Random.bits allows us have a seeded shuffle *)
  let shuffle_array l = 
    let tagged_arr = Array.map (fun c -> Random.bits (), c) l in
    let _ = Array.sort compare tagged_arr in
    Array.map (fun (_, b) -> b) tagged_arr


  (***** Create Region Distribution List *****)

  let rec node_regions_step l i acc =
    let num_nodes = !Parameters.General.num_nodes in
    let dist_regions = !Parameters.General.region_distribution in
    let n = Array.length dist_regions in
      if i < n then
        let rdist = (dist_regions.(i)) in
          if (List.length l) < int_of_float (Float.round ((float_of_int num_nodes) *. (rdist +. acc))) then
            node_regions_step (i::l) i acc
          else
            node_regions_step (i::l) (i+1) (rdist +. acc)
      else
      l

  (** uses the network parameters to return a list of integers, representing the region each node is assigned to *)
  let node_regions () : regions =
    if !Parameters.General.use_topology_file then
      (
        let open Yojson.Basic.Util in
          let ret = ref [] in
          let node_data = Parameters.General.parse_topology_file !Parameters.General.topology_filename in
          List.iter (
            fun node ->
              let region = node |> member "region" |> to_int in
              ret := !ret@[region];
          ) node_data;
          Array.of_list !ret
      )
    else
      shuffle_array (Array.of_list (node_regions_step [] 0 0.0))


  (***** Create Links between Nodes *****)

  (** condition for node with <nid> to be added as an outbound neighbor to node with <id> *)
  let can_add_neighbor id nid outbound_links inbound_links num_links :bool =
    let num_nodes        = !Parameters.General.num_nodes in
    let last_node        = (id = num_nodes) in (* ensure last node has the requried outbound links *)
    let id_outbound      = outbound_links.(id) in
    let nid_inbound      = inbound_links.(nid) in
    let already_outbound = List.exists (fun e -> e = nid) id_outbound in
    let already_inbound  = List.exists (fun e -> e = id) nid_inbound in
    let outbound_limit   = (List.length id_outbound) >= (num_links.(id)+1) in
    let inbound_limit    = (List.length nid_inbound) >= (num_links.(nid)+1) in
    let same_node        = id = nid in
    let valid_nodes      = (id >= 0) && (id < num_nodes) && (nid >= 0) && (nid < num_nodes) in
    (not same_node) && (not already_outbound) && (not already_inbound) && (not outbound_limit) && ((not inbound_limit) || last_node) && valid_nodes

  (** select neighbors for node with id = <id>, taking the link limitations in consideration *)
  let select_neighbors id nodes (inbound_links:(int list array)) (outbound_links:(int list array)) num_links =
    let candidates = shuffle_array nodes in 
    for i = 0 to (Array.length candidates)-1 do
      begin
      let candidate = (candidates.(i)) in
      if List.length outbound_links.(id) < (num_links.(id)+1) then
        if can_add_neighbor id candidate outbound_links inbound_links num_links then
          begin
          outbound_links.(id) <- [candidate]@outbound_links.(id);
          inbound_links.(candidate) <- [id]@inbound_links.(candidate)
          end
      end
    done

  (** uses the network parameters to return a list of int lists, representing the links each node has *)
  let node_links () : network_links =
    let num_nodes = !Parameters.General.num_nodes in
    if !Parameters.General.use_topology_file then
      (
        let open Yojson.Basic.Util in
          let ret = ref [] in
          let node_data = Parameters.General.parse_topology_file !Parameters.General.topology_filename in
          List.iter (
            fun node ->
              let links = node |> member "links" |> to_list in
              ret := !ret@[Array.of_list (List.map (fun x -> x |> to_int) links)];
          ) node_data;
          Array.of_list !ret
      )
    else
      (
        let nodes = Array.init num_nodes (fun c -> c) in
        let inbound_links:(int list array) = Array.make num_nodes [] in
        let outbound_links:(int list array) = Array.make num_nodes [] in
        let rec num_links_per_node l i acc = 
          let num_nodes = !Parameters.General.num_nodes in
          let dist_neighbors = !Parameters.General.degree_distribution in
          let n = Array.length dist_neighbors in
            if i < n then
              let rdist = (dist_neighbors.(i)) in
                if (List.length l) < int_of_float (Float.round ((float_of_int num_nodes) *. (rdist +. acc))) then
                  num_links_per_node (i::l) i acc
                else
                  num_links_per_node (i::l) (i+1) (rdist +. acc)
            else
            l
        in
        let num_links = (Array.of_list (num_links_per_node [] 0 0.0)) in
        for i = 0 to num_nodes-1 do
          select_neighbors i nodes inbound_links outbound_links num_links
        done;
        Array.map (fun x -> Array.of_list x) outbound_links
      )


  (*** End Hidden Operations ***)

  module ME = struct
    let label = "total-messages-exchanged"
    let use_intervals = false
    let format = 0
  end
  module MessagesExchanged = Simulator.Statistics.Make.CountAll(ME);;

  module MBE = struct
    let label = "megabytes-exchanged"
    let use_intervals = false
    let format = 0
  end
  module MegabytesExchanged = Simulator.Statistics.Make.CountAllF(MBE);;

  (* required types *)
  type msg   = Events.msg
  type paths = (int * int list * int * int * int) array array (* latency_sum, bandwidth_list, num_nodes_in_path, last_sender_in_path, latency between last_sender and recipient *)

  (* required data *)
  let regions = node_regions () (* region assigned to each node *)
  let links   = node_links ()   (* neighbours of each node *)

  (* data required for gossip abstraction *)
  let shortest_paths:(paths option ref) = ref None (* shortest path from each node, to all other nodes *)

  (* data required to handle bandwidth limits *)
    (* PER-LINK-BANDWIDTHS=TRUE *)
    (* to model upload bandwidth limits, we keep track of the timestamp when the bandwidth becomes available for the next message to be sent *)
    (* Note : we assume each message uses all available bandwidth, and therefore messages are sent in sequence, per link *)
    (* Note : bandwidth becomes available after the message is uploaded to the link *)
  module OQL = Map.Make(struct type t = int*int let compare = compare end);;
  let outgoing_queues_links = ref OQL.empty;;
    (* PER-LINK-BANDWIDTHS=FALSE *)
    (* same as before, but instead of each message using available link bandwidth, uses available node bandwidth *)
  module OQN = Map.Make(struct type t = int let compare = compare end);;
  let outgoing_queues_nodes = ref OQN.empty;;

  let get_links () = links

  let get_regions () = regions

  (***** Latency Calculation Operations *****)

  (* get mean latency from the parameters *)
  let get_mean_latency sender receiver =
    let region_sender   = regions.(sender) in
    let region_receiver = regions.(receiver) in
    let mean_latency    = (!Parameters.General.latency_table.(region_sender)).(region_receiver) in
    mean_latency

  (* from SimBlock -> latency according to 20% variance pareto distribution *)
  (* https://dsg-titech.github.io/simblock/ *)
  let extract_latency mean_latency =
    let shape = 0.2 *. (float_of_int mean_latency)  in
    let scale = float_of_int (mean_latency - 5) in
    int_of_float (Float.round (scale /. ((Random.float 1.0) ** (1.0 /. shape))))
  
  (* obtain a latency value between two nodes *)
  let get_latency sender receiver = 
    let mean_latency = get_mean_latency sender receiver in
    extract_latency mean_latency

  (* obtain bandwidth between two nodes *)
  let get_bandwidth sender receiver =
    let region_sender      = regions.(sender) in
    let region_receiver    = regions.(receiver) in
    let upload_bandwidth   = !Parameters.General.upload_bandwidth.(region_sender) in
    let download_bandwidth = !Parameters.General.download_bandwidth.(region_receiver) in
    min upload_bandwidth download_bandwidth

  (* get time needed to upload all pending messages to a given link *)
  let pending_upload_time_links sender receiver =
    let current_time = Simulator.Clock.get_timestamp () in
    let stored_available_timestamp =
      match OQL.find_opt (sender,receiver) !outgoing_queues_links with
      | Some(ts) -> ts
      | None -> 0
    in
    let next_available_timestamp = max stored_available_timestamp current_time in
    let wait_delay   = next_available_timestamp - current_time in
    outgoing_queues_links := OQL.add (sender,receiver) next_available_timestamp !outgoing_queues_links;
    wait_delay

  (* get time needed to upload all pending messages by the node *)
  let pending_upload_time_node sender =
    let current_time = Simulator.Clock.get_timestamp () in
    let stored_available_timestamp =
      match OQN.find_opt sender !outgoing_queues_nodes with
      | Some(ts) -> ts
      | None -> 0
    in
    let next_available_timestamp = max stored_available_timestamp current_time in
    let wait_delay   = next_available_timestamp - current_time in
    outgoing_queues_nodes := OQN.add sender next_available_timestamp !outgoing_queues_nodes;
    wait_delay

  (* send a message between two nodes *)
  let send sender receiver msg =
    let latency = get_latency sender receiver in
    let bandwidth = get_bandwidth sender receiver in
    let msg_size_bits = (Simulator.Size.to_bits (Message.get_size msg)) in
    let delay = msg_size_bits / (bandwidth / 1000) + (Message.processing_time msg)  in
    let arrival_time = 
      begin
        if !Parameters.General.limited_bandwidth then
          (
            if !Parameters.General.per_link_bandwidths then
              ( (* bandwidth limits are interpreted as per-link *)
                let wait_delay = pending_upload_time_links sender receiver in
                outgoing_queues_links := OQL.add (sender,receiver) ((OQL.find (sender,receiver) !outgoing_queues_links) + delay) !outgoing_queues_links;
                ((Simulator.Clock.get_timestamp ()) + latency + delay + wait_delay)
              )
            else
              ( (* bandwidth limits are interpreted as per-node *)
                let wait_delay = pending_upload_time_node sender in
                outgoing_queues_nodes := OQN.add sender ((OQN.find sender !outgoing_queues_nodes) + delay) !outgoing_queues_nodes;
                ((Simulator.Clock.get_timestamp ()) + latency + delay + wait_delay)
              )
          )
        else
          ((Simulator.Clock.get_timestamp ()) + latency + delay)
      end
    in
    let msg_event = Events.Message(sender,receiver,Simulator.Clock.get_timestamp (),arrival_time,msg) in
    MessagesExchanged.process sender 1;
    MegabytesExchanged.process sender (Simulator.Size.to_megabytes (Message.get_size msg));
    Queue.add_event msg_event

  (* get a node's neighbours *)
  let get_neighbours node =
    links.(node)

  (* send a message to a given node's neighbors *)
  let send_to_neighbors node msg =
    let n_neighbors = get_neighbours node in
    Array.iter (fun neighbor_id -> send node neighbor_id msg) n_neighbors

  (* Floyd Warshall's Algorithm -> https://en.wikipedia.org/wiki/Floyd%E2%80%93Warshall_algorithm#Algorithm *)
  let compute_shortest_paths () =
    let t = Sys.time () in
    print_endline "\t\t Computing shortest-paths between every pair of nodes...";
    let num_nodes = !Parameters.General.num_nodes in
    (* the distance of one node to itself is 0 *)
    (* the starting distance of one node to all others is infinity - represented by -1 *)
    let shortest_paths = 
      Array.init num_nodes (fun x -> Array.init num_nodes (fun y -> if x=y then (0,[],0,-1,0) else (-1,[],-1,-1,0)))
    in
    (* initialize the distance between each pair of nodes that possess a link, with the weight of the link *)
    for i=0 to num_nodes-1 do
      for j=0 to (Array.length links.(i)-1) do
        let neighbour = links.(i).(j) in
        let latency = get_mean_latency (i) (neighbour) in
        let bandwidth = get_bandwidth (i) (neighbour) in
        shortest_paths.(i).(neighbour) <- (latency,[bandwidth],1,i,latency)
      done
    done;
    for k=0 to num_nodes-1 do
      for i=0 to num_nodes-1 do
        for j=0 to num_nodes-1 do
          let (l1,b1,n1,_,_) = shortest_paths.(i).(k) in
          let (l2,b2,n2,last_sender2,last_latency) = shortest_paths.(k).(j) in
          let (l,_,_,_,_)    = shortest_paths.(i).(j) in
          if (l1 > -1) && (l2 > -1) then
            (
              if (l > l1 + l2)
                || (l = -1)
              then
                shortest_paths.(i).(j) <- (l1+l2,b1@b2,n1+n2,last_sender2,last_latency)
            )
        done
      done
    done;
    let elapsed_time = Sys.time () -. t in
    let s = Printf.sprintf "\t\t [DONE] Computed shortest-paths in %.2f seconds." elapsed_time in
    print_endline s;
    shortest_paths

  (* gossip abstraction that leverages the shortest paths *)
  (* Note : assumes limited-bandwidth=false *)
  let gossip sender msg =
    let msg_size = Simulator.Size.to_bits (Message.get_size msg) in
    let delay bandwidth =
      (msg_size / (bandwidth / 1000) + (Message.processing_time msg))
    in
    let num_nodes = !Parameters.General.num_nodes in
    let sp = 
      begin
        match !shortest_paths with
        | None -> 
          let p = compute_shortest_paths () in
          shortest_paths := Some(p);p
        | Some(p) -> p
      end
    in
    for i=0 to num_nodes-1 do
      if not (i = sender) then
      (
        let (l,b,_,last_sender,last_latency) = sp.(sender).(i) in
        let latency = extract_latency l in
        let time_elapsed_bandwidth = ref 0 in
        let last_time_elapsed_bandwidth = ref 0 in
        List.iter (fun x -> 
          let d = delay x in
          time_elapsed_bandwidth := !time_elapsed_bandwidth + d;
          last_time_elapsed_bandwidth := d
        ) b;
        let departure_time = (Simulator.Clock.get_timestamp ()) + (latency - last_latency) + (!time_elapsed_bandwidth - !last_time_elapsed_bandwidth) in (* when the last node begins sending the message to the target *) 
        let arrival_time = (Simulator.Clock.get_timestamp ()) + latency + !time_elapsed_bandwidth in
        let msg_event = Events.Message(last_sender,i,departure_time,arrival_time,msg) in
        Queue.add_event msg_event;
      )
    done;
    ()

    let clear () =
      outgoing_queues_links := OQL.empty;
      outgoing_queues_nodes := OQN.empty;;

end
