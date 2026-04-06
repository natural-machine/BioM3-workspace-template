#!/bin/bash
#=============================================================================
# Step 100: Build Dataset
#
# Constructs a finetuning dataset CSV from reference databases using
# biom3_build_dataset. The output CSV contains protein sequences, text
# descriptions, and metadata columns required by the downstream pipeline.
#
# USAGE:
#   ./pipeline/0100_build_dataset.sh <output_csv> [options]
#
# OPTIONS:
#   Additional flags are passed through to biom3_build_dataset.
#
# EXAMPLE:
#   ./pipeline/0100_build_dataset.sh data/MyFamily/MyFamily_dataset.csv
#
# OUTPUT:
#   <output_csv> — CSV with columns: primary_Accession, protein_sequence,
#                  [final]text_caption, pfam_label
#=============================================================================

set -euo pipefail

# --- Validate positional args ---
if [ "$#" -lt 1 ]; then
    echo "Usage: $0 <output_csv> [biom3_build_dataset options...]"
    echo ""
    echo "All additional arguments are passed through to biom3_build_dataset."
    echo ""
    echo "Example: $0 data/MyFamily/MyFamily_dataset.csv"
    exit 1
fi

output_csv=$1
shift

# --- Paths ---
projdir=$(cd "$(dirname "$0")/.." && pwd)
cd ${projdir}

export TORCH_FORCE_NO_WEIGHTS_ONLY_LOAD=1

echo "============================================="
echo "Step 100: Build Dataset (workflow v${BIOM3_WORKSPACE_VERSION:-unknown})"
echo "============================================="
echo "Output CSV: ${output_csv}"
echo ""

biom3_build_dataset \
    -o "${output_csv}" \
    "$@"

echo ""
echo "============================================="
echo "Dataset build complete."
echo "Output: ${output_csv}"
echo "============================================="
