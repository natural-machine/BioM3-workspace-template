#!/bin/bash
#=============================================================================
# Step 300: Finetune ProteoScribe
#
# Finetunes the pretrained ProteoScribe base model on the HDF5 dataset
# produced by Step 200. Uses a JSON training config for all hyperparameters
# and model architecture settings.
#
# USAGE:
#   ./pipeline/0300_finetune.sh <hdf5_file> <output_dir> [epochs] [options]
#
# OPTIONS:
#   --config PATH       JSON training config (default: configs/stage3_training/finetune.json)
#   --device DEVICE     Compute device (default: $BIOM3_DEVICE or cuda)
#
# EXAMPLE:
#   ./pipeline/0300_finetune.sh outputs/SH3/embeddings/SH3_dataset.compiled_emb.hdf5 outputs/SH3/finetuning
#   ./pipeline/0300_finetune.sh outputs/SH3/embeddings/SH3_dataset.compiled_emb.hdf5 outputs/SH3/finetuning 50
#   ./pipeline/0300_finetune.sh outputs/SH3/embeddings/SH3_dataset.compiled_emb.hdf5 outputs/SH3/finetuning \
#       --config configs/stage3_training/finetune.json
#
# INPUT:
#   <hdf5_file>: compiled embeddings from Step 2
#
# OUTPUT:
#   checkpoints/<run_id>/   — model weights and checkpoints
#   runs/<run_id>/          — logs, artifacts, metrics
#=============================================================================

set -euo pipefail

# --- Validate positional args ---
if [ "$#" -lt 2 ]; then
    echo "Usage: $0 <hdf5_file> <output_dir> [epochs] [--config PATH] [--device DEVICE]"
    echo "Example: $0 outputs/SH3/embeddings/SH3_dataset.compiled_emb.hdf5 outputs/SH3/finetuning 50"
    exit 1
fi

hdf5_file=$1
outdir=$2
shift 2

# Optional positional epoch arg
epochs=""
if [ "$#" -gt 0 ] && [[ "$1" != --* ]]; then
    epochs="$1"
    shift
fi

# --- Parse optional flags ---
config_path=""
device=""

while [ "$#" -gt 0 ]; do
    case "$1" in
        --config)
            config_path="$2"
            shift 2
            ;;
        --device)
            device="$2"
            shift 2
            ;;
        *)
            echo "Error: Unknown option: $1"
            exit 1
            ;;
    esac
done

# --- Paths ---
projdir=$(cd "$(dirname "$0")/.." && pwd)
cd ${projdir}

config_path="${config_path:-configs/stage3_training/finetune.json}"
device="${device:-${BIOM3_DEVICE:-cuda}}"

if [ ! -f "${hdf5_file}" ]; then
    echo "Error: HDF5 file not found: ${hdf5_file}"
    exit 1
fi

if [ ! -f "${config_path}" ]; then
    echo "Error: Config file not found: ${config_path}"
    exit 1
fi

# --- Run ID ---
datetime=$(date +%Y%m%d_%H%M%S)
run_id="finetune_e${epochs:-default}_V${datetime}"

export TORCH_FORCE_NO_WEIGHTS_ONLY_LOAD=1

echo "============================================="
echo "Step 300: Finetune ProteoScribe (workflow v${BIOM3_WORKSPACE_VERSION:-unknown})"
echo "============================================="
echo "Config:         ${config_path}"
echo "Training data:  ${hdf5_file}"
echo "Output dir:     ${outdir}"
if [ -n "${epochs}" ]; then echo "Epochs:         ${epochs}"; fi
echo "Device:         ${device}"
echo "Run ID:         ${run_id}"
echo ""
echo "Starting finetuning..."
echo ""

# Build CLI args — config provides all hyperparameters,
# CLI overrides only the per-run values.
cli_args=(
    --config_path "${config_path}"
    --primary_data_path "${hdf5_file}"
    --output_root "${outdir}"
    --run_id "${run_id}"
    --device "${device}"
)

if [ -n "${epochs}" ]; then
    cli_args+=(--epochs "${epochs}")
fi

biom3_pretrain_stage3 "${cli_args[@]}"

echo ""
echo "============================================="
echo "Finetuning complete."
echo "Checkpoints: ${outdir}/checkpoints/${run_id}/"
echo "Run logs:    ${outdir}/runs/${run_id}/"
echo "============================================="
