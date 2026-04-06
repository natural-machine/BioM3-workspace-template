#!/bin/bash
#=============================================================================
# Step 8: Launch BioM3 Web App
#
# Starts the BioM3 Streamlit web application for interactive exploration of
# pipeline outputs: view and align 3D structures, color residues by metrics,
# visualize diffusion unmasking order, and run BLAST searches.
#
# Data directories browsable in the app are configured in
# configs/app_settings.json. This is passed to biom3_app via --config.
#
# USAGE:
#   ./pipeline/09_webapp.sh [--port PORT]
#
# OPTIONS:
#   --port PORT    Streamlit server port (default: 8501)
#
# EXAMPLE:
#   ./pipeline/09_webapp.sh
#   ./pipeline/09_webapp.sh --port 8502
#
# REQUIRES:
#   - BioM3-dev installed with app extras: pip install "biom3[app]"
#   - Pipeline outputs in outputs/ (from Steps 1-7)
#=============================================================================

set -euo pipefail

# --- Parse optional flags ---
port=""

while [ "$#" -gt 0 ]; do
    case "$1" in
        --port)
            port="$2"
            shift 2
            ;;
        *)
            echo "Error: Unknown option: $1"
            echo "Usage: $0 [--port PORT]"
            exit 1
            ;;
    esac
done

# --- Paths ---
projdir=$(cd "$(dirname "$0")/.." && pwd)
cd "${projdir}"

config="${projdir}/configs/app_settings.json"

if [ ! -f "${config}" ]; then
    echo "Error: App config not found: ${config}"
    exit 1
fi

echo "============================================="
echo "Step 8: BioM3 Web App (workflow v${BIOM3_WORKFLOW_VERSION:-unknown})"
echo "============================================="
echo "Config:  ${config}"
echo "URL:     http://localhost:${port:-8501}"
echo ""

# --- Launch ---
biom3_args=(--config "${config}")
if [ -n "${port}" ]; then
    biom3_args+=(--server.port "${port}")
fi

biom3_app "${biom3_args[@]}"
