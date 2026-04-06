#!/bin/bash
#=============================================================================
# Step 200: Embedding
#
# Processes a CSV file containing protein sequences and text descriptions
# through the BioM3 embedding pipeline:
#   1. PenCL inference (Stage 1) — encodes sequences and text into embeddings
#   2. Facilitator sampling (Stage 2) — maps text embeddings into protein space
#   3. HDF5 compilation — packages embeddings for Stage 3 finetuning
#
# USAGE:
#   ./pipeline/0200_embedding.sh <input_csv> <output_dir> [options]
#
# OPTIONS:
#   --pencl_weights PATH          PenCL model weights (default: weights/PenCL/PenCL_V09152023_last.ckpt)
#   --facilitator_weights PATH    Facilitator model weights (default: weights/Facilitator/Facilitator_MMD15.ckpt/last.ckpt)
#   --pencl_config PATH           PenCL config (default: configs/inference/stage1_PenCL.json)
#   --facilitator_config PATH     Facilitator config (default: configs/inference/stage2_Facilitator.json)
#   --batch_size N                Batch size (default: 32)
#   --dataset_key KEY             HDF5 dataset key (default: MMD_data)
#   --device DEVICE               Compute device (default: $BIOM3_DEVICE or cuda)
#   --                            Pass remaining args through to biom3_embedding_pipeline
#
# EXAMPLE:
#   ./pipeline/0200_embedding.sh data/SH3/SH3_dataset.csv outputs/SH3/embeddings
#   ./pipeline/0200_embedding.sh data/SH3/SH3_dataset.csv outputs/SH3/embeddings --batch_size 64 --device cpu
#
# INPUT:
#   A CSV file with at minimum these columns:
#     - protein_sequence: amino acid sequences
#     - primary_Accession: unique identifier per entry
#     - A text/description column with natural language prompts
#
# OUTPUT:
#   <output_dir>/<prefix>.compiled_emb.hdf5
#=============================================================================

set -euo pipefail

# --- Validate positional args ---
if [ "$#" -lt 2 ]; then
    echo "Usage: $0 <input_csv> <output_dir> [options]"
    echo ""
    echo "Options:"
    echo "  --pencl_weights PATH          PenCL model weights"
    echo "  --facilitator_weights PATH    Facilitator model weights"
    echo "  --pencl_config PATH           PenCL config JSON"
    echo "  --facilitator_config PATH     Facilitator config JSON"
    echo "  --batch_size N                Batch size (default: 32)"
    echo "  --dataset_key KEY             HDF5 dataset key (default: MMD_data)"
    echo "  --device DEVICE               Compute device (default: cuda)"
    echo "  --                            Pass remaining args to biom3_embedding_pipeline"
    echo ""
    echo "Example: $0 data/SH3/SH3_dataset.csv outputs/SH3/embeddings"
    exit 1
fi

input_csv=$1
outdir=$2
shift 2

if [ ! -f "${input_csv}" ]; then
    echo "Error: Input file not found: ${input_csv}"
    exit 1
fi

# --- Parse optional flags ---
pencl_weights=""
facilitator_weights=""
pencl_config=""
facilitator_config=""
batch_size=""
dataset_key=""
device=""
extra_args=()

while [ "$#" -gt 0 ]; do
    case "$1" in
        --pencl_weights)
            pencl_weights="$2"
            shift 2
            ;;
        --facilitator_weights)
            facilitator_weights="$2"
            shift 2
            ;;
        --pencl_config)
            pencl_config="$2"
            shift 2
            ;;
        --facilitator_config)
            facilitator_config="$2"
            shift 2
            ;;
        --batch_size)
            batch_size="$2"
            shift 2
            ;;
        --dataset_key)
            dataset_key="$2"
            shift 2
            ;;
        --device)
            device="$2"
            shift 2
            ;;
        --)
            shift
            extra_args=("$@")
            break
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

pencl_weights="${pencl_weights:-weights/PenCL/PenCL_V09152023_last.ckpt}"
facilitator_weights="${facilitator_weights:-weights/Facilitator/Facilitator_MMD15.ckpt/last.ckpt}"
pencl_config="${pencl_config:-configs/inference/stage1_PenCL.json}"
facilitator_config="${facilitator_config:-configs/inference/stage2_Facilitator.json}"
batch_size="${batch_size:-32}"
dataset_key="${dataset_key:-MMD_data}"
device="${device:-${BIOM3_DEVICE:-cuda}}"

prefix=$(basename "${input_csv}" .csv)

export TORCH_FORCE_NO_WEIGHTS_ONLY_LOAD=1

echo "============================================="
echo "Step 200: Embedding (workflow v${BIOM3_WORKSPACE_VERSION:-unknown})"
echo "============================================="
echo "Input CSV:  ${input_csv}"
echo "Output dir: ${outdir}"
echo "Prefix:     ${prefix}"
echo "Device:     ${device}"
echo ""

biom3_embedding_pipeline \
    -i ${input_csv} \
    -o ${outdir} \
    --pencl_weights ${pencl_weights} \
    --facilitator_weights ${facilitator_weights} \
    --pencl_config ${pencl_config} \
    --facilitator_config ${facilitator_config} \
    --prefix ${prefix} \
    --batch_size ${batch_size} \
    --dataset_key ${dataset_key} \
    --device ${device} \
    "${extra_args[@]}"

echo ""
echo "============================================="
echo "Embedding complete."
echo "Output: ${outdir}/${prefix}.compiled_emb.hdf5"
echo "============================================="
