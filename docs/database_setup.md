# Database Setup and Caching

Step 100 (`biom3_build_dataset`) queries large protein databases that benefit from one-time preprocessing into indexed formats. This guide walks through syncing the source databases, building caches, and wiring them into your pipeline config. See [0100_build_dataset.md](0100_build_dataset.md) for full Step 100 usage.

## Prerequisites

- BioM3-dev installed (`pip install git+https://github.com/addison-nm/BioM3-dev.git@v0.1.0a2`)
- Access to BioM3-data-share on your machine
- Environment sourced (`source environment.sh`)

| Machine | BioM3-data-share root |
|---------|-----------------------|
| DGX Spark | `/data/data-share/BioM3-data-share` |
| Polaris (ALCF) | `/grand/NLDesignProtein/sharepoint/BioM3-data-share` |
| Aurora (ALCF) | `/flare/NLDesignProtein/sharepoint/BioM3-data-share` |

The examples below use `<ROOT>` as a placeholder for your machine's BioM3-data-share path.

## Step 1: Sync databases and datasets

### Reference databases

Create symlinks to the shared (read-only) database files:

```bash
./scripts/sync_databases.sh <ROOT>/databases data/databases --dry-run   # preview
./scripts/sync_databases.sh <ROOT>/databases data/databases             # create symlinks
```

This populates `data/databases/` with subdirectories: `swissprot/`, `trembl/`, `ncbi_taxonomy/`, `pfam/`, etc.

### Training CSVs

The two source CSVs required by `biom3_build_dataset`:

```bash
mkdir -p data/datasets
ln -s <ROOT>/data/datasets/fully_annotated_swiss_prot.csv data/datasets/
ln -s <ROOT>/data/datasets/Pfam_protein_text_dataset.csv data/datasets/
```

### Path resolution

Database paths are resolved in this order:

1. **CLI flags** (`--swissprot`, `--pfam`, `--databases_root`)
2. **Environment variable** `BIOM3_DATABASES_ROOT`
3. **Config file** `configs/dbio_config.json`

For most workspace use, the default `dbio_config.json` works once symlinks are in place.

## Step 2: Build caches

Caches are one-time preprocessing steps that trade disk space for dramatically faster pipeline runs. All caches should be written to `data/.cache/` (gitignored, writable) since the shared database directories are read-only.

```bash
mkdir -p data/.cache
```

### Convert source CSVs to Parquet

Converts the large CSV files to Parquet for 5-10x faster queries. Database readers auto-detect `.parquet` files alongside `.csv` files and use them automatically.

```bash
biom3_convert_to_parquet data/datasets/Pfam_protein_text_dataset.csv \
    -o data/.cache/Pfam_protein_text_dataset.parquet

biom3_convert_to_parquet data/datasets/fully_annotated_swiss_prot.csv \
    -o data/.cache/fully_annotated_swiss_prot.parquet
```

The `-o` flag writes the output to `data/.cache/` instead of next to the (read-only symlinked) source CSV. When using `-o`, pass the Parquet path explicitly in your pipeline config:

```bash
biom3_build_dataset -p PF00018 -o outputs/SH3 \
    --swissprot data/.cache/fully_annotated_swiss_prot.parquet \
    --pfam data/.cache/Pfam_protein_text_dataset.parquet
```

If your `data/datasets/` directory is writable (local copies, not symlinks), you can omit `-o` and the Parquet file will be placed alongside the CSV for automatic detection.

### Build annotation cache

Parses UniProt `.dat.gz` files into compact Parquet caches for instant caption enrichment via `--annotation_cache`. Without this, enrichment either parses the raw `.dat.gz` (hours for TrEMBL) or hits the UniProt REST API (slow, requires internet).

```bash
# Swiss-Prot (fast, ~minutes, ~100 MB output)
biom3_build_annotation_cache \
    --dat data/databases/swissprot/uniprot_sprot.dat.gz \
    -o data/.cache/swissprot_annotations.parquet

# TrEMBL (slow, several hours, ~few GB output)
biom3_build_annotation_cache \
    --dat data/databases/trembl/uniprot_trembl.dat.gz \
    -o data/.cache/trembl_annotations.parquet
```

Swiss-Prot covers only ~568K reviewed entries. Pfam accessions are predominantly from TrEMBL (unreviewed). For full enrichment coverage, build both caches.

### Build taxonomy SQLite index

Indexes the 11 GB `prot.accession2taxid.gz` (1.55B rows) into a SQLite database for instant accession-to-taxid lookups. Without this, each `--add_taxonomy` run streams the full file (~10-15 min).

```bash
biom3_build_taxid_index \
    data/databases/ncbi_taxonomy/prot.accession2taxid.gz \
    -o data/.cache/accession2taxid.sqlite
```

### Summary

| Cache | Source | Source size | Output size | Build time | When needed |
|-------|--------|-------------|-------------|------------|-------------|
| Parquet CSVs | Training CSVs | 35 GB + 1.5 GB | ~6 GB + ~300 MB | ~10-30 min | Multiple Step 100 runs |
| Annotation (Swiss-Prot) | `uniprot_sprot.dat.gz` | 661 MB | ~100 MB | Minutes | `--enrich_pfam` |
| Annotation (TrEMBL) | `uniprot_trembl.dat.gz` | 161 GB | ~few GB | Several hours | `--enrich_pfam` |
| Taxonomy index | `prot.accession2taxid.gz` | 11 GB | ~25 GB | ~30-60 min | `--add_taxonomy` |

## Step 3: Reference caches in the pipeline config

### TOML config (`[build_dataset].extra_args`)

```toml
[build_dataset]
pfam_ids = ["PF00018"]
training_csv = "outputs/SH3/SH3_dataset.csv"
extra_args = [
    "--config",           "configs/dbio_config.json",
    "--enrich_pfam",
    "--annotation_cache", "data/.cache/swissprot_annotations.parquet",
                          "data/.cache/trembl_annotations.parquet",
    "--add_taxonomy",
    "--taxid_index",      "data/.cache/accession2taxid.sqlite",
]
```

### Direct CLI

```bash
./pipeline/0100_build_dataset.sh data/SH3/ --pfam-ids PF00018 \
    --enrich-pfam \
    --annotation-cache data/.cache/swissprot_annotations.parquet \
                       data/.cache/trembl_annotations.parquet \
    --add-taxonomy \
    --taxid-index data/.cache/accession2taxid.sqlite
```

See `configs/pipelines/_template.toml` for the full set of configurable options and [0100_build_dataset.md](0100_build_dataset.md) for the complete CLI reference.

## Quick reference

All commands in sequence (DGX Spark paths shown; substitute `<ROOT>` for other machines):

```bash
# 1. Sync databases and datasets
./scripts/sync_databases.sh /data/data-share/BioM3-data-share/databases data/databases
mkdir -p data/datasets
ln -s /data/data-share/BioM3-data-share/data/datasets/fully_annotated_swiss_prot.csv data/datasets/
ln -s /data/data-share/BioM3-data-share/data/datasets/Pfam_protein_text_dataset.csv data/datasets/

# 2. Build caches (one-time)
mkdir -p data/.cache
biom3_convert_to_parquet data/datasets/Pfam_protein_text_dataset.csv \
    -o data/.cache/Pfam_protein_text_dataset.parquet
biom3_convert_to_parquet data/datasets/fully_annotated_swiss_prot.csv \
    -o data/.cache/fully_annotated_swiss_prot.parquet
biom3_build_annotation_cache \
    --dat data/databases/swissprot/uniprot_sprot.dat.gz \
    -o data/.cache/swissprot_annotations.parquet
biom3_build_annotation_cache \
    --dat data/databases/trembl/uniprot_trembl.dat.gz \
    -o data/.cache/trembl_annotations.parquet
biom3_build_taxid_index \
    data/databases/ncbi_taxonomy/prot.accession2taxid.gz \
    -o data/.cache/accession2taxid.sqlite

# 3. Run pipeline
python run_pipeline.py configs/pipelines/myconfig.toml --steps 100
```

## Troubleshooting

**"Permission denied" when writing Parquet/SQLite files**: The shared database directories are read-only. Always use `-o` to write caches to `data/.cache/` or another writable location.

**TrEMBL annotation cache build is killed (OOM)**: The parser is memory-efficient but can still require significant RAM on large files. Run in a `screen`/`tmux` session on a machine with sufficient memory.

**"File not found" for `.dat.gz` files**: Ensure `sync_databases.sh` was run and the relevant subdirectory is populated. TrEMBL (`uniprot_trembl.dat.gz`) is not always synced by default due to its size (161 GB) -- verify its presence with `ls data/databases/trembl/`.

**SQLite index takes too long**: Building the 1.55B-row index takes 30-60 minutes. Run it in a `screen`/`tmux` session and let it complete in the background.
