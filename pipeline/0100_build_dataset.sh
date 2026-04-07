#!/bin/bash
#=============================================================================
# Step 100: Build Dataset
#
# Constructs a finetuning dataset CSV from reference databases using
# biom3_build_dataset. Extracts protein sequences and text captions from
# SwissProt and Pfam by Pfam family ID, optionally enriches captions with
# UniProt annotations, and optionally adds NCBI taxonomy lineage.
#
# The output CSV contains protein sequences, text descriptions, and metadata
# columns required by the downstream embedding pipeline (Step 200).
#
# USAGE:
#   ./pipeline/0100_build_dataset.sh <output_dir> --pfam_ids <id1> [id2...] [options]
#
# OPTIONS (passed through to biom3_build_dataset):
#   --pfam_ids ID [ID...]         Pfam family IDs to extract (required)
#   --output_filename NAME        Output CSV filename (default: dataset.csv)
#   --swissprot PATH              Path to fully_annotated_swiss_prot.csv
#   --pfam PATH                   Path to Pfam_protein_text_dataset.csv
#   --databases_root PATH         Override database root path
#   --config PATH                 Path to dbio config JSON
#   --enrich_pfam                 Enrich Pfam captions with UniProt annotations
#   --annotation_cache PATH...    Pre-built annotation Parquet cache(s) (fastest enrichment)
#   --uniprot_dat PATH...         Local UniProt .dat.gz file(s) for offline enrichment
#   --add_taxonomy                Add NCBI taxonomy lineage column
#   --taxonomy_filter EXPR...     Filter by taxonomy rank (e.g. "superkingdom=Bacteria")
#   --taxid_index PATH            Pre-built SQLite accession-to-taxid index
#   --chunk_size N                Chunk size for reading Pfam CSV (default: 500000)
#
# EXAMPLE (basic — paths from biom3 config):
#   ./pipeline/0100_build_dataset.sh data/SH3/ --pfam_ids PF00018
#
# EXAMPLE (explicit database paths from BioM3-data-share):
#   ./pipeline/0100_build_dataset.sh data/SH3/ --pfam_ids PF00018 \
#       --swissprot ../BioM3-data-share/data/datasets/fully_annotated_swiss_prot.csv \
#       --pfam ../BioM3-data-share/data/datasets/Pfam_protein_text_dataset.csv
#
# EXAMPLE (enriched captions from local .dat files):
#   ./pipeline/0100_build_dataset.sh data/SH3/ --pfam_ids PF00018 \
#       --enrich_pfam \
#       --uniprot_dat ../BioM3-data-share/databases/swissprot/uniprot_sprot.dat.gz \
#                     ../BioM3-data-share/databases/trembl/uniprot_trembl.dat.gz
#
# EXAMPLE (enriched captions from pre-built annotation cache — fastest):
#   ./pipeline/0100_build_dataset.sh data/SH3/ --pfam_ids PF00018 \
#       --enrich_pfam \
#       --annotation_cache data/databases/trembl/trembl_annotations.parquet
#
# EXAMPLE (enrichment + taxonomy filtering):
#   ./pipeline/0100_build_dataset.sh data/SH3/ --pfam_ids PF00018 \
#       --enrich_pfam --add_taxonomy \
#       --taxonomy_filter "superkingdom=Bacteria" \
#       --taxid_index data/databases/ncbi_taxonomy/accession2taxid.sqlite
#
# INPUT:
#   Two training CSVs (resolved from biom3 config or passed explicitly):
#     - fully_annotated_swiss_prot.csv  (~570K rows, curated annotations)
#     - Pfam_protein_text_dataset.csv   (~44.8M rows, domain sequences)
#
# OUTPUT:
#   <output_dir>/<filename>.csv             — Final dataset (4 columns, default: dataset.csv)
#   <output_dir>/<filename>_annotations.csv — Intermediate with all annot_* columns
#   <output_dir>/build_manifest.json        — Reproducibility manifest
#   <output_dir>/pfam_ids.csv               — Pfam IDs used for extraction
#   <output_dir>/build.log                  — Build log
#=============================================================================

set -euo pipefail

# --- Validate positional args ---
if [ "$#" -lt 1 ]; then
    echo "Usage: $0 <output_dir> --pfam_ids <id1> [id2...] [options]"
    echo ""
    echo "Constructs a finetuning dataset CSV from SwissProt and Pfam databases."
    echo ""
    echo "Options (passed through to biom3_build_dataset):"
    echo "  --pfam_ids ID [ID...]         Pfam family IDs to extract (required)"
    echo "  --swissprot PATH              Path to fully_annotated_swiss_prot.csv"
    echo "  --pfam PATH                   Path to Pfam_protein_text_dataset.csv"
    echo "  --databases_root PATH         Override database root path"
    echo "  --enrich_pfam                 Enrich captions with UniProt annotations"
    echo "  --annotation_cache PATH...    Pre-built annotation Parquet cache(s)"
    echo "  --uniprot_dat PATH...         Local UniProt .dat.gz file(s)"
    echo "  --add_taxonomy                Add NCBI taxonomy lineage"
    echo "  --taxonomy_filter EXPR...     Filter by rank (e.g. \"superkingdom=Bacteria\")"
    echo "  --taxid_index PATH            Pre-built SQLite accession-to-taxid index"
    echo "  --chunk_size N                Chunk size for Pfam CSV (default: 500000)"
    echo ""
    echo "Example:"
    echo "  $0 data/SH3/ --pfam_ids PF00018"
    echo "  $0 data/SH3/ --pfam_ids PF00018 --enrich_pfam --annotation_cache cache.parquet"
    exit 1
fi

output_dir=$1
shift

# --- Check dependencies ---
if ! command -v biom3_build_dataset &> /dev/null; then
    echo "Error: biom3_build_dataset not found on PATH."
    echo "Ensure biom3 is installed:"
    echo "  pip install git+https://github.com/addison-nm/BioM3-dev.git@v0.1.0a2"
    exit 1
fi

# --- Paths ---
projdir=$(cd "$(dirname "$0")/.." && pwd)
cd ${projdir}

export TORCH_FORCE_NO_WEIGHTS_ONLY_LOAD=1

mkdir -p "${output_dir}"

echo "============================================="
echo "Step 100: Build Dataset (workflow v${BIOM3_WORKSPACE_VERSION:-unknown})"
echo "============================================="
echo "Output dir: ${output_dir}"
echo ""

biom3_build_dataset \
    -o "${output_dir}" \
    "$@"

echo ""
echo "============================================="
echo "Dataset build complete."
echo "Output: ${output_dir}/dataset.csv"
echo "============================================="
