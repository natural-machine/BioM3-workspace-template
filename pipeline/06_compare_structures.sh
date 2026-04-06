#!/bin/bash
#=============================================================================
# Step 6: Structure Comparison with TMalign
#
# Compares ColabFold-predicted structures (Step 4) against BLAST reference
# structures (Step 5) using TMalign. Produces a CSV of structural similarity
# metrics (TM-score, RMSD, sequence identity) for each query-reference pair.
#
# Requires TMalign to be installed and on PATH.
#
# USAGE:
#   ./pipeline/07_compare_structures.sh <colabfold_csv> <blast_tsv> <structures_dir> <reference_dir> <output_dir>
#
# EXAMPLE:
#   ./pipeline/07_compare_structures.sh \
#       outputs/SH3/structures/colabfold_results.csv \
#       outputs/SH3/blast/blast_hit_results.tsv \
#       outputs/SH3/structures \
#       outputs/SH3/blast/reference_structures \
#       outputs/SH3/comparison
#
# INPUT:
#   <colabfold_csv>:  colabfold_results.csv from Step 4 (maps query IDs to PDB filenames)
#   <blast_tsv>:      blast_hit_results.tsv from Step 5 (query-reference pairs)
#   <structures_dir>: directory containing ColabFold prompt_*/ subdirectories
#   <reference_dir>:  directory containing downloaded reference PDB files
#
# OUTPUT:
#   <output_dir>/results.csv              (TM-score, RMSD, sequence identity per pair)
#   <output_dir>/logs/*.TMalign.log       (individual TMalign output logs)
#=============================================================================

set -euo pipefail

# --- Validate args ---
if [ "$#" -ne 5 ]; then
    echo "Usage: $0 <colabfold_csv> <blast_tsv> <structures_dir> <reference_dir> <output_dir>"
    echo "Example: $0 outputs/SH3/structures/colabfold_results.csv outputs/SH3/blast/blast_hit_results.tsv outputs/SH3/structures outputs/SH3/blast/reference_structures outputs/SH3/comparison"
    exit 1
fi

colabfold_csv=$1
blast_tsv=$2
structures_dir=$3
reference_dir=$4
outdir=$5

if [ ! -f "${colabfold_csv}" ]; then
    echo "Error: ColabFold results not found: ${colabfold_csv}"
    exit 1
fi

if [ ! -f "${blast_tsv}" ]; then
    echo "Error: BLAST results not found: ${blast_tsv}"
    exit 1
fi

if [ ! -d "${structures_dir}" ]; then
    echo "Error: Structures directory not found: ${structures_dir}"
    exit 1
fi

if [ ! -d "${reference_dir}" ]; then
    echo "Error: Reference structures directory not found: ${reference_dir}"
    exit 1
fi

# --- Check dependencies ---
if ! command -v TMalign &> /dev/null; then
    echo "Error: TMalign not found on PATH."
    echo "Install TMalign from: https://zhanggroup.org/TM-align/"
    exit 1
fi

# --- Paths ---
projdir=$(cd "$(dirname "$0")/.." && pwd)
cd ${projdir}

logdir="${outdir}/logs"
results_fpath="${outdir}/results.csv"

mkdir -p "${outdir}"
mkdir -p "${logdir}"

echo "============================================="
echo "Step 6: Structure Comparison with TMalign (workflow v${BIOM3_WORKSPACE_VERSION:-unknown})"
echo "============================================="
echo "ColabFold CSV:   ${colabfold_csv}"
echo "BLAST TSV:       ${blast_tsv}"
echo "Structures dir:  ${structures_dir}"
echo "Reference dir:   ${reference_dir}"
echo "Output dir:      ${outdir}"
echo ""

# --- Build query-to-PDB mapping from ColabFold results ---
declare -A QUERY2PDB

# Skip header and read CSV
while IFS=',' read -r structure pLDDT pTM pdbfilename; do
    prompt=${structure%_replica_*}
    QUERY2PDB["$structure"]="${structures_dir}/${prompt}/${pdbfilename}.pdb"
done < <(tail -n +2 "${colabfold_csv}")

echo "Loaded ${#QUERY2PDB[@]} structure mappings from ColabFold results."
echo ""

# --- Write results header ---
echo "query_id,pdbid,chain,TM,q_length,r_length,aligned_length,RMSD,seq_id" > "${results_fpath}"

# --- Run TMalign for each BLAST hit ---
echo "Running TMalign comparisons..."
count=0
skipped=0

while IFS=$'\t' read -r id pdbstr _; do
    pdb_id=$(echo "$pdbstr" | cut -d'|' -f2)
    chain=$(echo "$pdbstr" | cut -d'|' -f3)
    seq_pdbfpath="${QUERY2PDB["$id"]:-}"
    ref_pdbfpath="${reference_dir}/${pdb_id}.pdb"

    if [[ -z "${seq_pdbfpath}" ]]; then
        skipped=$((skipped + 1))
        continue
    fi

    if [[ ! -e "${ref_pdbfpath}" || ! -e "${seq_pdbfpath}" ]]; then
        skipped=$((skipped + 1))
        continue
    fi

    count=$((count + 1))
    tmalign_outfpath="${logdir}/${id}_v_${pdb_id}.TMalign.log"

    TMalign "${seq_pdbfpath}" "${ref_pdbfpath}" > "${tmalign_outfpath}" 2>&1

    # Parse TMalign output
    tm_score=$(grep "TM-score=" "$tmalign_outfpath" | grep "Chain_2" | awk '{print $2}')
    len_query=$(grep "Length of Chain_1:" "$tmalign_outfpath" | awk '{print $4}')
    len_ref=$(grep "Length of Chain_2:" "$tmalign_outfpath" | awk '{print $4}')
    read aligned_length rmsd seq_id < <(
        grep "Aligned length=" "$tmalign_outfpath" | \
        sed -E 's/.*Aligned length= *([0-9]+), RMSD= *([0-9.]+), Seq_ID=n_identical\/n_aligned= *([0-9.]+).*/\1 \2 \3/'
    )

    echo "${id},${pdb_id},${chain},${tm_score},${len_query},${len_ref},${aligned_length},${rmsd},${seq_id}" >> "${results_fpath}"
done < "${blast_tsv}"

nresults=$(($(wc -l < "${results_fpath}") - 1))
echo ""
echo "Completed ${count} comparisons (${skipped} skipped due to missing files)."
echo ""

echo "============================================="
echo "Structure comparison complete."
echo "Results: ${results_fpath} (${nresults} entries)"
echo "Logs:    ${logdir}/"
echo "============================================="
