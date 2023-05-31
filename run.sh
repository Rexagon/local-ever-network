#!/usr/bin/env bash

set -eE

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

help_msg='Usage: run.sh --node-path PATH --tools-path PATH [OPTIONS]

Options:
  -h,--help                               Print this help message and exit
  --node-path PATH                        Path to the node repo
  --betterscale-tools-path PATH           Path to the betterscale-tools repo
  --zerostate PATH                        Path to zerostate config
  --rebuild-node                          Build node repo before running the network
  --rebuild-betterscale-tools             Build betterscale-tools before running the network
  --output PATH                           Output directory with nodes
'

print_help() {
  echo "$help_msg"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
  -h | --help)
    print_help
    exit 0
    ;;
  -c | --configs)
    configs="$2"
    shift
    if [ "$#" -gt 0 ]; then
      shift
    else
      echo 'ERROR: Expected configs folder\n'
      print_help
      exit 1
    fi
    ;;
  -o | --output)
    output="$2"
    shift
    shift
    if [ "$#" -gt 0 ]; then
      shift
    else
      echo 'ERROR: Expected output folder\n'
      print_help
      exit 1
    fi
    ;;
  --betterscale-tools-path)
    bstools_root="$2"
    shift
    if [ "$#" -gt 0 ]; then
      shift
    else
      echo 'ERROR: Expected betterscale-tools path\n'
      print_help
      exit 1
    fi
    [[ $# -eq 0 ]] && {
      echo -e "ERROR: Expected betterscale-tools path\n"
      print_help
      exit 1
    }
    ;;
  --node-path)
    node_root="$2"
    shift
    if [ "$#" -gt 0 ]; then
      shift
    else
      echo 'ERROR: Expected ever-node repo path\n'
      print_help
      exit 1
    fi
    ;;
  --rebuild-node)
    rebuild_node=true
    shift
    ;;
  --rebuild-betterscale-tools)
    rebuild_bstool=true
    shift
    ;;
  *) # unknown option
    echo -e "ERROR: Unknown option $1 \n"
    print_help
    exit 1
    ;;
  esac
done

[[ -z $node_root ]] && {
  echo "ERROR: ever-node repo path not set"
  print_help
  exit 1
}
[[ -z $bstools_root ]] && {
  echo "ERROR: betterscale-tools repo path not set"
  print_help
  exit 1
}

if [[ -n $rebuild_node ]]; then
  echo "INFO: rebuilding node"
  pushd "$node_root" >/dev/null
  cargo build --release --features "telemetry"
  popd >/dev/null
fi

if [[ -n $rebuild_bstool ]]; then
  echo "INFO: rebuilding betterscale-tools"
  pushd "$bstools_root" >/dev/null
  cargo build --release
  popd >/dev/null
fi

node_root="$(cd "$node_root" && pwd -P)"
node_target="$node_root/target/release"
bstools_target="$bstools_root/target/release"

pkill ton_node &>/dev/null || true

logs_dir="$script_dir/logs"
output_dir="$script_dir/$output"

mkdir -p "$output_dir"
mkdir -p "$logs_dir"

echo -e "INFO: build nodes configs using betterscale"

"$bstools_target/betterscale" -- zerostate --config "$configs" --output "$output"

nodes=$(ls -d $output/node* | wc -l)

echo -e "INFO: starting nodes...\nNODES=$nodes"

for ((n = 0; n <= $((nodes - 1)); n++)); do
  echo "      * starting node #$n"
  node_configs_dir="$output/node$n"
  pushd "$node_configs_dir" >/dev/null
  cp config.json default-config.json
  "$node_target/ton_node" --configs ./ -z "$output_dir/zerostate" >>"${logs_dir}/node_$n.output" 2>&1 &
  rm default-config.json
  popd >/dev/null
done

echo -e "INFO: starting nodes... done\n$(date)"
