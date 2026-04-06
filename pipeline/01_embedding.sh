#!/bin/bash
#=============================================================================
# Step 1: Embedding
#
# Processes a CSV file containing protein sequences and text descriptions
# through the BioM3 embedding pipeline:
#   1. PenCL inference (Stage 1) — encodes sequences and text into embeddings
#   2. Facilitator sampling (Stage 2) — maps text embeddings into protein space
#   3. HDF5 compilation — packages embeddings for Stage 3 finetuning
#
# USAGE:
#   ./pipeline/01_embedding.sh <input_csv> <output_dir>
#
# EXAMPLE:
#   ./pipeline/01_embedding.sh data/SH3/SH3_dataset.csv outputs/SH3/embeddings
#   ./pipeline/01_embedding.sh data/CM/CM_dataset.csv outputs/CM/embeddings
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

# --- Validate args ---
if [ "$#" -ne 2 ]; then
    echo "Usage: $0 <input_csv> <output_dir>"
    echo "Example: $0 data/SH3/SH3_dataset.csv outputs/SH3/embeddings"
    exit 1
fi

input_csv=$1
outdir=$2

if [ ! -f "${input_csv}" ]; then
    echo "Error: Input file not found: ${input_csv}"
    exit 1
fi

# --- Paths ---
projdir=$(cd "$(dirname "$0")/.." && pwd)
cd ${projdir}

pencl_weights=weights/PenCL/PenCL_V09152023_last.ckpt
facilitator_weights=weights/Facilitator/Facilitator_MMD15.ckpt/last.ckpt
config1=configs/inference/stage1_PenCL.json
config2=configs/inference/stage2_Facilitator.json

prefix=$(basename "${input_csv}" .csv)

export TORCH_FORCE_NO_WEIGHTS_ONLY_LOAD=1

echo "============================================="
echo "Step 1: Embedding (workflow v${BIOM3_WORKFLOW_VERSION:-unknown})"
echo "============================================="
echo "Input CSV:  ${input_csv}"
echo "Output dir: ${outdir}"
echo "Prefix:     ${prefix}"
echo ""

biom3_embedding_pipeline \
    -i ${input_csv} \
    -o ${outdir} \
    --pencl_weights ${pencl_weights} \
    --facilitator_weights ${facilitator_weights} \
    --pencl_config ${config1} \
    --facilitator_config ${config2} \
    --prefix ${prefix} \
    --batch_size 32 \
    --dataset_key MMD_data \
    --device cuda

echo ""
echo "============================================="
echo "Embedding complete."
echo "Output: ${outdir}/${prefix}.compiled_emb.hdf5"
echo "============================================="
