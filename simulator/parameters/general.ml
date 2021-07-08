(* this file will contain the simulation parameters *)
(* reads from JSON file so that changing parameters doesn't require recompiling the code *)

let parameters_file = ref "default-parameters.json"

(* general parameters and default values *)
let num_nodes = ref 10
let end_block_height = ref 5
let seed = ref 123

(* TODO : add other parameters as they are needed *)

(* network parameters and default values *)
let num_regions = ref 6
let num_links = ref 5
type lte = int list
(* latency is in millisseconds *)
let latency_table = ref [
  [32; 124; 184; 198; 151; 189];
  [124; 11; 227; 237; 252; 294];
  [184; 227; 88; 325; 301; 322];
  [198; 237; 325; 85; 58; 198];
  [151; 252; 301; 58; 12; 126];
  [189; 294; 322; 198; 126; 16]]
let region_distribution = ref [0.3316; 0.4998; 0.0090; 0.1177; 0.0224; 0.0195]
let degree_distribution = ref [0.025; 0.050; 0.075; 0.10; 0.20; 0.30; 0.40; 0.50; 0.60; 0.70; 0.80; 0.85; 0.90; 0.95; 0.97; 0.97; 0.98; 0.99; 0.995; 1.0]
(* bandwidths are in bits per second *)
let download_bandwidth = ref [52000000; 40000000; 18000000; 22800000; 22800000; 29900000; 6000000]
let upload_bandwidth = ref [4700000; 8100000; 1800000; 5300000; 3400000; 5200000; 6000000]


(* pos parameters *)
let avg_coins   = ref 4000
let stdev_coins = ref 2000
let reward      = ref 0.01

(* pow parameters *)
let interval           = ref 600000
let avg_mining_power   = ref 400000
let stdev_mining_power = ref 100000





(* auxiliary functions *)
let get_general_param json param =
  let open Yojson.Basic.Util in
  json |> member "general" |> member param

let get_network_param json param =
  let open Yojson.Basic.Util in
  json |> member "network" |> member param

let () =
  if Array.length Sys.argv > 2 then parameters_file := Sys.argv.(1);
  let json = Yojson.Basic.from_file !parameters_file in
  let open Yojson.Basic.Util in
  num_nodes := get_general_param json "num-nodes" |> to_int;
  end_block_height := get_general_param json "end-block-height" |> to_int;
  seed := get_general_param json "seed" |> to_int; Random.init !seed;
  num_regions := get_network_param json "num-regions" |> to_int;
  num_links := get_network_param json "num-links" |> to_int;
  interval := get_general_param json "pow_target_interval" |> to_int;
  avg_mining_power := get_general_param json "avg_mining_power" |> to_int;
  stdev_mining_power := get_general_param json "stdev_mining_power" |> to_int;
  reward := get_general_param json "reward" |> to_float;
  avg_coins := get_general_param json "avg_coins" |> to_int;
  stdev_coins := get_general_param json "stdev_coins" |> to_int;
  region_distribution := get_network_param json "region-distribution" |> to_list |> filter_float;
  degree_distribution := get_network_param json "degree-distribution" |> to_list |> filter_float;
  download_bandwidth := get_network_param json "download-bandwidth" |> to_list |> filter_int;
  upload_bandwidth := get_network_param json "upload-bandwidth" |> to_list |> filter_int;
  let latency_table_tmp = get_network_param json "latency-table" |> to_list in
  latency_table := List.map (fun x -> List.map (fun y -> to_int y) (to_list x)) latency_table_tmp


