(* this file will contain the simulation parameters *)
(* reads from JSON file so that changing parameters doesn't require recompiling the code *)

let parameters_file = "parameters.json"

(* general parameters and default values *)
let num_nodes = ref 10
let end_block_height = ref 5
let seed = ref 123

(* TODO : add other parameters as they are needed *)

(* network parameters and default values *)
let num_regions = ref 6
let num_links = ref 5
type lte = int list
let latency_table = ref [
  [32; 124; 184; 198; 151; 189];
  [124; 11; 227; 237; 252; 294];
  [184; 227; 88; 325; 301; 322];
  [198; 237; 325; 85; 58; 198];
  [151; 252; 301; 58; 12; 126];
  [189; 294; 322; 198; 126; 16]]
let region_distribution = ref [0.3316; 0.4998; 0.0090; 0.1177; 0.0224; 0.0195]
let degree_distribution = ref [0.025; 0.050; 0.075; 0.10; 0.20; 0.30; 0.40; 0.50; 0.60; 0.70; 0.80; 0.85; 0.90; 0.95; 0.97; 0.97; 0.98; 0.99; 0.995; 1.0]

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

let get_pow_param json param =
  let open Yojson.Basic.Util in
  json |> member "pow" |> member param

let get_pos_param json param =
  let open Yojson.Basic.Util in
  json |> member "pos" |> member param

let () =
  let json = Yojson.Basic.from_file parameters_file in
  let open Yojson.Basic.Util in
  num_nodes := get_general_param json "num-nodes" |> to_int;
  end_block_height := get_general_param json "end-block-height" |> to_int;
  seed := get_general_param json "seed" |> to_int; Random.init !seed;
  num_regions := get_network_param json "num-regions" |> to_int;
  num_links := get_network_param json "num-links" |> to_int;
  interval := get_pow_param json "interval" |> to_int;
  avg_mining_power := get_pow_param json "avg_mining_power" |> to_int;
  stdev_mining_power := get_pow_param json "stdev_mining_power" |> to_int;
  reward := get_pos_param json "reward" |> to_float;
  avg_coins := get_pos_param json "avg_coins" |> to_int;
  stdev_coins := get_pos_param json "stdev_coins" |> to_int







  
  (*
  TODO : parse arrays from JSON
  region_distribution := get_network_param json "region-distribution" |> to_list |> filter_float;
  degree_distribution := get_network_param json "degree-distribution" |> to_list |> filter_float;
  latency_table := get_network_param json "latency-table" |> to_list |> filter_list |> filter_int;
  *)


