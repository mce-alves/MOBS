(* this file will contain the simulation parameters *)
(* reads from JSON file so that changing parameters doesn't require recompiling the code *)

let parameters_file = ref "default-parameters.json"

(* general parameters and default values *)
let protocol = ref "algorand"
let num_nodes = ref 10
let end_block_height = ref 5
let base_seed = ref 123
let seed = ref 123
let num_batches = ref 1
let current_batch = ref 1
let max_timestamp = ref 0
let timestamp_limit = ref false
let verbose = ref true

(* network parameters and default values *)
let num_regions = ref 6
let num_links = ref 8
type lte = int list
(* latency is in millisseconds *)
let latency_table = ref (Array.of_list (List.map (fun x -> Array.of_list x) [
  [32; 124; 184; 198; 151; 189];
  [124; 11; 227; 237; 252; 294];
  [184; 227; 88; 325; 301; 322];
  [198; 237; 325; 85; 58; 198];
  [151; 252; 301; 58; 12; 126];
  [189; 294; 322; 198; 126; 16]]))
let region_distribution = ref (Array.of_list [0.3316; 0.4998; 0.0090; 0.1177; 0.0224; 0.0195])
let degree_distribution = ref (Array.of_list [0.025; 0.025; 0.025; 0.025; 0.1; 0.1; 0.1; 0.1; 0.1; 0.1; 0.1; 0.05; 0.05; 0.05; 0.02; 0.0; 0.01; 0.01; 0.005; 0.005])
(* bandwidths are in bits per second *)
let limited_bandwidth = ref true
let per_link_bandwidths = ref false
let download_bandwidth = ref (Array.of_list [52000000; 40000000; 18000000; 22800000; 22800000; 29900000; 6000000])
let upload_bandwidth = ref (Array.of_list [4700000; 8100000; 1800000; 5300000; 3400000; 5200000; 6000000])

(* pos parameters *)
let avg_coins   = ref 4000.0
let stdev_coins = ref 2000.0
let reward      = ref 0.01

(* pow parameters *)
let interval           = ref 600000
let avg_mining_power   = ref 400000
let stdev_mining_power = ref 100000

(* general adversary parameters *)
let num_bad_nodes = ref 0
let become_bad_timestamp = ref 0

(* offline nodes *)
let num_offline_nodes = ref 0
let become_offline_timestamp = ref 0
let become_online_timestamp = ref 0

(* parametrize nodes by topology file *)
let use_topology_file = ref false
let topology_filename = ref "../topology_files/topology.json"



(* auxiliary functions *)
let get_general_param json param =
  let open Yojson.Basic.Util in
  json |> member "general" |> member param

let get_network_param json param =
  let open Yojson.Basic.Util in
  json |> member "network" |> member param

let parse_topology_file filename =
  let open Yojson.Basic.Util in
  let json = Yojson.Basic.from_file filename in
  let node_data = json |> member "nodes" |> to_list in
  node_data

let () =
  if Array.length Sys.argv > 2 then parameters_file := Sys.argv.(1);
  let json = Yojson.Basic.from_file !parameters_file in
  let open Yojson.Basic.Util in
  protocol := get_general_param json "protocol" |> to_string;
  num_nodes := get_general_param json "num-nodes" |> to_int;
  end_block_height := get_general_param json "end-block-height" |> to_int;
  base_seed := get_general_param json "seed" |> to_int;
  num_batches := get_general_param json "number-of-batches" |> to_int;
  num_regions := get_network_param json "num-regions" |> to_int;
  interval := get_general_param json "pow_target_interval" |> to_int;
  avg_mining_power := get_general_param json "avg_mining_power" |> to_int;
  stdev_mining_power := get_general_param json "stdev_mining_power" |> to_int;
  reward := get_general_param json "reward" |> to_number;
  avg_coins := get_general_param json "avg_coins" |> to_number;
  stdev_coins := get_general_param json "stdev_coins" |> to_number;
  max_timestamp := get_general_param json "timestamp-limit" |> to_int;
  verbose := get_general_param json "verbose-output" |> to_bool;
  num_bad_nodes := get_general_param json "bad_nodes" |> to_int;
  become_bad_timestamp := get_general_param json "become_bad_timestamp" |> to_int;
  num_offline_nodes := get_general_param json "offline_nodes" |> to_int;
  become_offline_timestamp := get_general_param json "become_offline_timestamp" |> to_int;
  become_online_timestamp := get_general_param json "become_online_timestamp" |> to_int;
  if !max_timestamp > 0 then timestamp_limit := true;
  region_distribution := Array.of_list (get_network_param json "region-distribution" |> to_list |> filter_number);
  degree_distribution := Array.of_list (get_network_param json "degree-distribution" |> to_list |> filter_number);
  limited_bandwidth := get_network_param json "limited-bandwidth" |> to_bool;
  per_link_bandwidths := get_network_param json "per-link-bandwidths" |> to_bool;
  download_bandwidth := Array.of_list (get_network_param json "download-bandwidth" |> to_list |> filter_int);
  upload_bandwidth := Array.of_list (get_network_param json "upload-bandwidth" |> to_list |> filter_int);
  let latency_table_tmp = get_network_param json "latency-table" |> to_list in
  latency_table := (Array.of_list
    (List.map (fun x -> Array.of_list (List.map (fun y -> to_int y) (to_list x))) latency_table_tmp));
  use_topology_file := get_general_param json "use-topology-file" |> to_bool;
  topology_filename := get_general_param json "topology-file" |> to_string;
  if !use_topology_file then 
    (
      let node_data = parse_topology_file !topology_filename in
      num_nodes := List.length node_data
    )


