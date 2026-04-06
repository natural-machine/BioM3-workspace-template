#!/bin/bash
#=============================================================================
# Step 5: BLAST Homology Search
#
# Runs a BLAST protein search (blastp) on generated sequences to find
# homologous sequences in SwissProt, PDB, NR, or other databases. By default,
# performs a remote search against SwissProt. Use --db pdbaa for a PDB search
# with automatic reference structure downloads.
#
# Requires the `blast-env` conda environment to be active.
#
# USAGE:
#   ./pipeline/06_blast_search.sh <fasta_file> <output_dir> [options]
#
# OPTIONS:
#   --db <name_or_path>    BLAST database name or path to local copy (default: swissprot)
#                          Known NCBI names: pdbaa, nr, swissprot, refseq_protein,
#                                           env_nr, tsa_nr, pat
#                          If a path (contains /), forces local search.
#   --remote               Use NCBI remote search (default for known db names)
#   --local                Use local search (requires local database files)
#   --threads N            Number of threads for local search (default: 16)
#   --max-targets N        Max target sequences per query (default: 5)
#   --no-download-pdbs     Skip downloading PDB files for hits
#
# EXAMPLE (remote SwissProt search, default):
#   ./pipeline/06_blast_search.sh outputs/SH3/samples/all_sequences.fasta outputs/SH3/blast
#
# EXAMPLE (remote PDB search with structure downloads):
#   ./pipeline/06_blast_search.sh outputs/SH3/samples/all_sequences.fasta outputs/SH3/blast --db pdbaa
#
# EXAMPLE (local SwissProt or NR search):
#   ./pipeline/06_blast_search.sh outputs/SH3/samples/all_sequences.fasta outputs/SH3/blast --db /path/to/swissprot_blast/swissprot --threads 16
#   ./pipeline/06_blast_search.sh outputs/SH3/samples/all_sequences.fasta outputs/SH3/blast --db /path/to/nr_blast/nr --threads 16
#
# INPUT:
#   <fasta_file>: concatenated FASTA of generated sequences (from Step 3 --fasta_merge)
#
# OUTPUT:
#   <output_dir>/blast_hit_results.tsv
#   <output_dir>/reference_structures/   (downloaded PDB files, if applicable)
#=============================================================================

set -euo pipefail

# --- Validate positional args ---
if [ "$#" -lt 2 ]; then
    echo "Usage: $0 <fasta_file> <output_dir> [options]"
    echo ""
    echo "Options:"
    echo "  --db <name_or_path>    BLAST database name or local path (default: swissprot)"
    echo "                         Known names: pdbaa, nr, swissprot, refseq_protein,"
    echo "                                      env_nr, tsa_nr, pat"
    echo "  --remote               Use NCBI remote search (default for known db names)"
    echo "  --local                Use local search (requires local database files)"
    echo "  --threads N            Threads for local search (default: 16)"
    echo "  --max-targets N        Max target sequences (default: 5)"
    echo "  --no-download-pdbs     Skip downloading PDB files"
    echo ""
    echo "Example: $0 outputs/SH3/samples/all_sequences.fasta outputs/SH3/blast"
    exit 1
fi

fasta_file=$1
outdir=$2
shift 2

if [ ! -f "${fasta_file}" ]; then
    echo "Error: FASTA file not found: ${fasta_file}"
    exit 1
fi

# --- Check dependencies ---
if ! command -v blastp &> /dev/null; then
    echo "Error: blastp not found on PATH."
    echo "Please activate the blast-env conda environment:"
    echo "  conda activate blast-env"
    exit 1
fi

# --- Parse optional flags ---
db="swissprot"
remote=""
threads=16
max_targets=5
download_pdbs=""  # auto-detect based on db

while [ "$#" -gt 0 ]; do
    case "$1" in
        --db)
            db="$2"
            shift 2
            ;;
        --remote)
            remote="yes"
            shift
            ;;
        --local)
            remote="no"
            shift
            ;;
        --threads)
            threads="$2"
            shift 2
            ;;
        --max-targets)
            max_targets="$2"
            shift 2
            ;;
        --no-download-pdbs)
            download_pdbs="no"
            shift
            ;;
        *)
            echo "Error: Unknown option: $1"
            exit 1
            ;;
    esac
done

# Known NCBI remote database names
known_remote_dbs="pdbaa nr swissprot refseq_protein env_nr tsa_nr pat"

# Databases whose hits have PDB IDs (eligible for structure download)
pdb_dbs="pdbaa"

# Auto-detect remote and download settings
if [[ "${db}" == */* ]]; then
    # Path provided — always local
    remote="${remote:-no}"
    download_pdbs="${download_pdbs:-no}"
elif echo " ${known_remote_dbs} " | grep -q " ${db} "; then
    # Known NCBI database name — default to remote
    remote="${remote:-yes}"
    if echo " ${pdb_dbs} " | grep -q " ${db} "; then
        download_pdbs="${download_pdbs:-yes}"
    else
        download_pdbs="${download_pdbs:-no}"
    fi
else
    # Unknown name — assume local (user may have BLASTDB set)
    remote="${remote:-no}"
    download_pdbs="${download_pdbs:-no}"
fi

# --- Paths ---
projdir=$(cd "$(dirname "$0")/.." && pwd)
cd ${projdir}

mkdir -p "${outdir}"

results_fpath="${outdir}/blast_hit_results.tsv"

echo "============================================="
echo "Step 5: BLAST Homology Search (workflow v${BIOM3_WORKFLOW_VERSION:-unknown})"
echo "============================================="
echo "Query FASTA:  ${fasta_file}"
echo "Output dir:   ${outdir}"
echo "Database:     ${db}"
echo "Remote:       ${remote}"
echo "Max targets:  ${max_targets}"
if [ "${remote}" = "no" ]; then
    echo "Threads:      ${threads}"
fi
echo "Download PDBs: ${download_pdbs}"
echo ""

# --- Build blastp command ---
echo "[1/2] Running BLAST search..."
blast_args=(
    -query "${fasta_file}"
    -db "${db}"
    -max_target_seqs "${max_targets}"
    -outfmt "6 qseqid sseqid stitle pident length evalue bitscore"
    -out "${results_fpath}"
)

if [ "${remote}" = "yes" ]; then
    blast_args+=(-remote)
else
    blast_args+=(-num_threads "${threads}")
fi

blastp "${blast_args[@]}"

nhits=$(wc -l < "${results_fpath}")
echo "[1/2] Done. Found ${nhits} hits."
echo ""

# --- Download PDB files for top hits ---
if [ "${download_pdbs}" = "yes" ]; then
    echo "[2/2] Downloading reference PDB files..."
    ref_dir="${outdir}/reference_structures"
    mkdir -p "${ref_dir}"
    unfound_fpath="${ref_dir}/not_found.txt"
    > "${unfound_fpath}"

    awk '{print $2}' "${results_fpath}" | cut -d'|' -f2 | sort -u | while read pdb; do
        outfile="${ref_dir}/${pdb}.pdb"
        if [ -f "${outfile}" ]; then
            echo "  ${pdb}.pdb already exists, skipping."
            continue
        fi
        url="https://files.rcsb.org/download/${pdb}.pdb"
        wget -q -O "${outfile}" "${url}" 2>/dev/null || true
        if [ ! -s "${outfile}" ]; then
            echo "${pdb}" >> "${unfound_fpath}"
            rm -f "${outfile}"
            echo "  Warning: PDB ${pdb} not found at RCSB."
        else
            echo "  Downloaded ${pdb}.pdb"
        fi
    done

    num_not_found=$(wc -l < "${unfound_fpath}")
    if [ "${num_not_found}" -gt 0 ]; then
        echo ""
        echo "  Warning: ${num_not_found} PDB files could not be downloaded."
        echo "  See: ${unfound_fpath}"
    fi
    echo "[2/2] Done."
else
    echo "[2/2] Skipping PDB download (--no-download-pdbs or non-PDB database)."
fi

echo ""
echo "============================================="
echo "BLAST search complete."
echo "Results: ${results_fpath}"
if [ "${download_pdbs}" = "yes" ]; then
    echo "PDBs:    ${outdir}/reference_structures/"
fi
echo "============================================="
