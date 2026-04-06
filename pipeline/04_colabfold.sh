#!/bin/bash
#=============================================================================
# Step 4: Structure Prediction with ColabFold
#
# Runs ColabFold (AlphaFold2) structure prediction on per-prompt FASTA files
# produced by Step 3 (with --fasta). After all predictions complete, parses
# the ColabFold log files to extract pLDDT and pTM scores into a summary CSV.
#
# Requires the `colabfold` conda environment to be active.
#
# USAGE:
#   ./pipeline/05_colabfold.sh <fasta_dir> <output_dir>
#
# EXAMPLE:
#   ./pipeline/05_colabfold.sh outputs/SH3/samples outputs/SH3/structures
#   ./pipeline/05_colabfold.sh outputs/CM/samples outputs/CM/structures
#
# INPUT:
#   <fasta_dir>: directory containing per-prompt FASTA files (prompt_0.fasta,
#                prompt_1.fasta, ...) from Step 3 --fasta output
#   <output_dir>: directory for ColabFold output (PDBs and logs)
#
# OUTPUT:
#   <output_dir>/prompt_<i>/          (ColabFold PDB files and logs per prompt)
#   <output_dir>/colabfold_results.csv (summary: structure,pLDDT,pTM,pdbfilename)
#=============================================================================

set -euo pipefail

# --- Validate args ---
if [ "$#" -ne 2 ]; then
    echo "Usage: $0 <fasta_dir> <output_dir>"
    echo "Example: $0 outputs/SH3/samples outputs/SH3/structures"
    exit 1
fi

fasta_dir=$1
outdir=$2

if [ ! -d "${fasta_dir}" ]; then
    echo "Error: FASTA directory not found: ${fasta_dir}"
    exit 1
fi

# --- Check dependencies ---
if ! command -v colabfold_batch &> /dev/null; then
    echo "Error: colabfold_batch not found on PATH."
    echo "Please activate the colabfold conda environment:"
    echo "  conda activate colabfold"
    exit 1
fi

# --- Paths ---
projdir=$(cd "$(dirname "$0")/.." && pwd)
cd ${projdir}

mkdir -p "${outdir}"

echo "============================================="
echo "Step 4: Structure Prediction with ColabFold (workflow v${BIOM3_WORKFLOW_VERSION:-unknown})"
echo "============================================="
echo "FASTA dir:  ${fasta_dir}"
echo "Output dir: ${outdir}"
echo ""

# --- Discover FASTA files ---
fasta_files=$(ls "${fasta_dir}/"prompt_*".fasta" 2>/dev/null | sort -V)
nfasta=$(echo "${fasta_files}" | wc -l)

if [ -z "${fasta_files}" ]; then
    echo "Error: No FASTA files found matching: ${fasta_dir}/prompt_*.fasta"
    exit 1
fi

echo "Found ${nfasta} FASTA files to process."
echo ""

# --- Run ColabFold on each FASTA ---
echo "[1/2] Running ColabFold structure prediction..."
count=0
for fasta in ${fasta_files}; do
    count=$((count + 1))
    # Extract prompt index from filename (e.g. prompt_3.fasta → 3)
    fname=$(basename "${fasta}")
    prompt_idx=$(echo "${fname}" | sed -E "s/prompt_([0-9]+)\.fasta/\1/")
    prompt_outdir="${outdir}/prompt_${prompt_idx}"
    mkdir -p "${prompt_outdir}"

    echo "  [${count}/${nfasta}] Predicting structures for prompt_${prompt_idx}..."
    colabfold_batch "${fasta}" "${prompt_outdir}"
done
echo "[1/2] Done."
echo ""

# --- Parse ColabFold log files ---
echo "[2/2] Parsing ColabFold results..."
results_csv="${outdir}/colabfold_results.csv"
echo "structure,pLDDT,pTM,pdbfilename" > "${results_csv}"

for prompt_dir in $(ls -d "${outdir}/prompt_"*/ 2>/dev/null | sort -V); do
    logfile="${prompt_dir}log.txt"
    if [ ! -f "${logfile}" ]; then
        echo "  Warning: No log.txt found in ${prompt_dir}, skipping."
        continue
    fi

    awk '
        /Query [0-9]+\/[0-9]+:/ {
            match($0, /Query [0-9]+\/[0-9]+: ([^ ]+)/, m)
            query = m[1]
        }
        /rank_001_/ {
            match($0, /(rank_001_[^ ]+)/, r)
            match($0, /pLDDT=([0-9.]+)/, a)
            match($0, /pTM=([0-9.]+)/, b)
            pdbfilename = query "_unrelaxed_" r[1]
            printf "%s,%s,%s,%s\n", query, a[1], b[1], pdbfilename
        }
    ' "${logfile}" >> "${results_csv}"
done

nresults=$(($(wc -l < "${results_csv}") - 1))
echo "[2/2] Done. Parsed ${nresults} structure results."
echo ""

echo "============================================="
echo "ColabFold prediction complete."
echo "Structures: ${outdir}/prompt_*/"
echo "Results:    ${results_csv}"
echo "============================================="
