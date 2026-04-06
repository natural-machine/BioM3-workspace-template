#!/bin/bash
#=============================================================================
# Step 4: Convert Generated Sequences to FASTA
#
# Converts the ProteoScribe .pt output from Step 3 into per-prompt FASTA
# files and a single concatenated FASTA. The number of prompts and replicas
# is detected automatically from the .pt file contents.
#
# USAGE:
#   ./pipeline/04_samples_to_fasta.sh <input_pt> <output_dir>
#
# EXAMPLE:
#   ./pipeline/04_samples_to_fasta.sh outputs/SH3/generation/SH3_prompts.ProteoScribe_output.pt outputs/SH3/samples
#   ./pipeline/04_samples_to_fasta.sh outputs/CM/generation/CM_prompts.ProteoScribe_output.pt outputs/CM/samples
#
# INPUT:
#   <input_pt>: .pt file from Step 3 (ProteoScribe generation output)
#
# OUTPUT:
#   <output_dir>/<prefix>_prompt_{i}_samples.fasta   (one per prompt)
#   <output_dir>/generated_seqs_allprompts.fasta      (all prompts concatenated)
#=============================================================================

set -euo pipefail

# --- Validate args ---
if [ "$#" -ne 2 ]; then
    echo "Usage: $0 <input_pt> <output_dir>"
    echo "Example: $0 outputs/SH3/generation/SH3_prompts.ProteoScribe_output.pt outputs/SH3/samples"
    exit 1
fi

input_pt=$1
outdir=$2

if [ ! -f "${input_pt}" ]; then
    echo "Error: Input file not found: ${input_pt}"
    exit 1
fi

# --- Paths ---
projdir=$(cd "$(dirname "$0")/.." && pwd)
cd ${projdir}

# Extract prefix: strip .ProteoScribe_output.pt, fallback to stripping .pt
fname=$(basename "${input_pt}")
if [[ "${fname}" == *.ProteoScribe_output.pt ]]; then
    prefix="${fname%.ProteoScribe_output.pt}"
else
    prefix="${fname%.pt}"
fi

mkdir -p "${outdir}"

echo "============================================="
echo "Step 4: Convert Generated Sequences to FASTA"
echo "============================================="
echo "Input:      ${input_pt}"
echo "Output dir: ${outdir}"
echo "Prefix:     ${prefix}"
echo ""

# --- Convert .pt to per-prompt FASTA files ---
echo "[1/2] Converting .pt to per-prompt FASTA files..."
python scripts/samples_to_fasta.py \
    -i "${input_pt}" \
    -o "${outdir}/${prefix}_prompt_{}_samples.fasta"

echo "[1/2] Done."
echo ""

# --- Concatenate all per-prompt FASTA into one file ---
echo "[2/2] Concatenating FASTA files..."
concat_fpath="${outdir}/generated_seqs_allprompts.fasta"
> "${concat_fpath}"

for fasta in $(ls "${outdir}/${prefix}_prompt_"*"_samples.fasta" 2>/dev/null | sort -V); do
    cat "${fasta}" >> "${concat_fpath}"
done

nfiles=$(ls "${outdir}/${prefix}_prompt_"*"_samples.fasta" 2>/dev/null | wc -l)
echo "[2/2] Done. Concatenated ${nfiles} FASTA files."
echo ""

echo "============================================="
echo "FASTA conversion complete."
echo "Per-prompt: ${outdir}/${prefix}_prompt_*_samples.fasta"
echo "Combined:   ${concat_fpath}"
echo "============================================="
