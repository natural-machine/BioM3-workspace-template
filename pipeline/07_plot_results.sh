#!/bin/bash
#=============================================================================
# Step 7: Plot Structural Comparison Results
#
# Generates strip plots for TM-score, RMSD, and sequence identity from the
# TMalign comparison results (Step 6). Optionally includes a pLDDT plot
# from ColabFold results (Step 4).
#
# USAGE:
#   ./pipeline/08_plot_results.sh <results_csv> <output_dir> [--colabfold-csv <path>]
#
# EXAMPLE:
#   ./pipeline/08_plot_results.sh \
#       outputs/SH3/comparison/results.csv \
#       outputs/SH3/images \
#       --colabfold-csv outputs/SH3/structures/colabfold_results.csv
#
# INPUT:
#   <results_csv>: results.csv from Step 6 (TMalign comparison metrics)
#
# OUTPUT:
#   <output_dir>/TM_scores.png
#   <output_dir>/RMSD_scores.png
#   <output_dir>/seqID_scores.png
#   <output_dir>/pLDDT_scores.png   (if --colabfold-csv provided)
#=============================================================================

set -euo pipefail

# --- Validate args ---
if [ "$#" -lt 2 ]; then
    echo "Usage: $0 <results_csv> <output_dir> [--colabfold-csv <path>]"
    echo "Example: $0 outputs/SH3/comparison/results.csv outputs/SH3/images --colabfold-csv outputs/SH3/structures/colabfold_results.csv"
    exit 1
fi

results_csv=$1
outdir=$2
shift 2

if [ ! -f "${results_csv}" ]; then
    echo "Error: Results CSV not found: ${results_csv}"
    exit 1
fi

# --- Paths ---
projdir=$(cd "$(dirname "$0")/.." && pwd)
cd ${projdir}

mkdir -p "${outdir}"

echo "============================================="
echo "Step 7: Plot Structural Comparison Results (workflow v${BIOM3_WORKSPACE_VERSION:-unknown})"
echo "============================================="
echo "Results CSV: ${results_csv}"
echo "Output dir:  ${outdir}"

# --- Build python command ---
plot_args=(
    --results "${results_csv}"
    --outdir "${outdir}"
)

# Pass through any remaining flags (e.g. --colabfold-csv)
while [ "$#" -gt 0 ]; do
    case "$1" in
        --colabfold-csv)
            echo "ColabFold:   $2"
            plot_args+=(--colabfold-csv "$2")
            shift 2
            ;;
        *)
            echo "Error: Unknown option: $1"
            exit 1
            ;;
    esac
done

echo ""

python scripts/make_plots.py "${plot_args[@]}"

echo ""
echo "============================================="
echo "Plotting complete."
echo "Plots: ${outdir}/"
echo "============================================="
