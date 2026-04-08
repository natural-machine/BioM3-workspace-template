#!/bin/bash
#=============================================================================
# Step 9000: Export Pipeline Outputs
#
# Copies or symlinks selected outputs from a completed pipeline run to
# user-specified destinations, driven by an export.config TOML file.
# Non-destructive on the source and idempotent.
#
# USAGE:
#   ./pipeline/9000_export.sh <export_config> <outputs_dir> [--dry-run] [--skip-missing]
#
# OPTIONS:
#   --dry-run        Print actions that would be taken without touching FS
#   --skip-missing   Warn and continue when a src does not exist (default: exit)
#
# EXAMPLE:
#   ./pipeline/9000_export.sh export.config outputs/SH3
#   ./pipeline/9000_export.sh export.config outputs/SH3 --dry-run
#
# INPUT:
#   <export_config>: TOML file with [[entry]] blocks (src, dst, mode)
#   <outputs_dir>:   per-family outputs root (src paths are relative to this)
#
# OUTPUT:
#   Files or symlinks at the dst paths listed in <export_config>.
#=============================================================================

set -euo pipefail

# --- Validate args ---
if [ "$#" -lt 2 ]; then
    echo "Usage: $0 <export_config> <outputs_dir> [--dry-run] [--skip-missing]"
    echo "Example: $0 export.config outputs/SH3 --dry-run"
    exit 1
fi

export_config=$1
outputs_dir=$2
shift 2

if [ ! -f "${export_config}" ]; then
    echo "Error: Export config not found: ${export_config}"
    exit 1
fi

if [ ! -d "${outputs_dir}" ]; then
    echo "Error: Outputs directory not found: ${outputs_dir}"
    exit 1
fi

# --- Paths ---
projdir=$(cd "$(dirname "$0")/.." && pwd)
cd "${projdir}"

echo "============================================="
echo "Step 9000: Export Pipeline Outputs (workflow v${BIOM3_WORKSPACE_VERSION:-unknown})"
echo "============================================="
echo "Config:      ${export_config}"
echo "Outputs dir: ${outputs_dir}"
echo ""

python scripts/export_outputs.py "${export_config}" "${outputs_dir}" "$@"

echo ""
echo "============================================="
echo "Export complete."
echo "============================================="
