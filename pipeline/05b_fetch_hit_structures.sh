#!/bin/bash
#=============================================================================
# Step 5b: Fetch Reference Structures for SwissProt BLAST Hits
#
# Resolves 3D structures for UniProt accessions found in BLAST results.
# For each hit, tries to download an experimental PDB structure from RCSB,
# falling back to AlphaFold DB predicted structures when no experimental
# structure is available.
#
# PDB cross-references are resolved either from a local uniprot_sprot.dat.gz
# (auto-detected at ../BioM3-data-share/databases/swissprot/) or via the
# UniProt REST API.
#
# Structures are saved as {accession}.pdb in <output_dir>/reference_structures/,
# which integrates directly with Step 6 (06_compare_structures.sh).
#
# USAGE:
#   ./pipeline/06b_fetch_hit_structures.sh <blast_tsv> <output_dir> [options]
#
# OPTIONS:
#   --swissprot-dat <path>   Path to local uniprot_sprot.dat.gz for offline
#                            PDB lookup (auto-detected if available)
#   --no-local-dat           Skip auto-detection of local DAT file, use API
#   --alphafold-only         Skip experimental PDB lookup, use AlphaFold only
#   --experimental-only      Skip AlphaFold fallback, experimental PDB only
#
# EXAMPLE (auto-detect local DAT, hybrid download):
#   ./pipeline/06b_fetch_hit_structures.sh \
#       outputs/SH3/blast/blast_hit_results.tsv \
#       outputs/SH3/blast
#
# EXAMPLE (AlphaFold only, skip PDB lookup):
#   ./pipeline/06b_fetch_hit_structures.sh \
#       outputs/SH3/blast/blast_hit_results.tsv \
#       outputs/SH3/blast --alphafold-only
#
# INPUT:
#   <blast_tsv>: blast_hit_results.tsv from Step 5
#
# OUTPUT:
#   <output_dir>/reference_structures/   (downloaded PDB files)
#   <output_dir>/structure_manifest.tsv  (accession, source, metadata)
#=============================================================================

set -euo pipefail

# --- Validate positional args ---
if [ "$#" -lt 2 ]; then
    echo "Usage: $0 <blast_tsv> <output_dir> [options]"
    echo ""
    echo "Options:"
    echo "  --swissprot-dat <path>   Path to local uniprot_sprot.dat.gz"
    echo "  --no-local-dat           Skip local DAT auto-detection, use UniProt API"
    echo "  --alphafold-only         Download only AlphaFold predicted structures"
    echo "  --experimental-only      Download only experimental PDB structures"
    echo ""
    echo "Example: $0 outputs/SH3/blast/blast_hit_results.tsv outputs/SH3/blast"
    exit 1
fi

blast_tsv=$1
outdir=$2
shift 2

if [ ! -f "${blast_tsv}" ]; then
    echo "Error: BLAST results file not found: ${blast_tsv}"
    exit 1
fi

# --- Parse optional flags ---
swissprot_dat=""
no_local_dat=""
alphafold_only=""
experimental_only=""

while [ "$#" -gt 0 ]; do
    case "$1" in
        --swissprot-dat)
            swissprot_dat="$2"
            shift 2
            ;;
        --no-local-dat)
            no_local_dat="yes"
            shift
            ;;
        --alphafold-only)
            alphafold_only="yes"
            shift
            ;;
        --experimental-only)
            experimental_only="yes"
            shift
            ;;
        *)
            echo "Error: Unknown option: $1"
            exit 1
            ;;
    esac
done

# --- Paths ---
projdir=$(cd "$(dirname "$0")/.." && pwd)
cd "${projdir}"

# Auto-detect local SwissProt DAT file
if [ -z "${swissprot_dat}" ] && [ -z "${no_local_dat}" ] && [ -z "${alphafold_only}" ]; then
    dat_candidate="${projdir}/../BioM3-data-share/databases/swissprot/uniprot_sprot.dat.gz"
    if [ -f "${dat_candidate}" ]; then
        swissprot_dat="${dat_candidate}"
    fi
fi

echo "============================================="
echo "Step 5b: Fetch Reference Structures (workflow v${BIOM3_WORKFLOW_VERSION:-unknown})"
echo "============================================="
echo "BLAST results: ${blast_tsv}"
echo "Output dir:    ${outdir}"
if [ -n "${swissprot_dat}" ]; then
    echo "SwissProt DAT: ${swissprot_dat}"
else
    echo "PDB lookup:    UniProt API"
fi
if [ -n "${alphafold_only}" ]; then
    echo "Mode:          AlphaFold only"
elif [ -n "${experimental_only}" ]; then
    echo "Mode:          Experimental only"
else
    echo "Mode:          Experimental + AlphaFold fallback"
fi
echo ""

# --- Build Python command ---
python_args=(
    "${projdir}/scripts/fetch_hit_structures.py"
    "${blast_tsv}"
    "${outdir}"
)

if [ -n "${swissprot_dat}" ]; then
    python_args+=(--swissprot-dat "${swissprot_dat}")
fi

if [ -n "${alphafold_only}" ]; then
    python_args+=(--alphafold-only)
fi

if [ -n "${experimental_only}" ]; then
    python_args+=(--experimental-only)
fi

python "${python_args[@]}"

echo ""
echo "============================================="
echo "Structure fetching complete."
echo "Structures: ${outdir}/reference_structures/"
echo "Manifest:   ${outdir}/structure_manifest.tsv"
echo "============================================="
