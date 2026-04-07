# Step 100: Build Dataset

Step 100 constructs a finetuning dataset CSV from reference databases using `biom3_build_dataset`. It extracts protein sequences and text captions from SwissProt and Pfam by Pfam family ID, optionally enriches captions with UniProt annotations, and optionally adds NCBI taxonomy lineage. The output is a standard 4-column CSV ready for Step 200 (Embedding).

## When to use Step 100

- **Use Step 100** when you want to build a training dataset from reference databases for a specific Pfam family (or families).
- **Skip Step 100** when you already have a CSV with the required columns (`primary_Accession`, `protein_sequence`, `[final]text_caption`, `pfam_label`). Set `training_csv` in your TOML config to point at your CSV and start at Step 200.

## Required inputs

Step 100 queries two pre-processed training CSVs:

| File | Rows | Size | Contents |
|------|------|------|----------|
| `fully_annotated_swiss_prot.csv` | ~570K | ~1.5 GB | Curated UniProt/Swiss-Prot entries with text captions |
| `Pfam_protein_text_dataset.csv` | ~44.8M | ~35 GB | Pfam domain sequences with family-level captions |

These are available in BioM3-data-share:

| Machine | Datasets path |
|---------|--------------|
| DGX Spark | `/data/data-share/BioM3-data-share/data/datasets` |
| Polaris (ALCF) | `/grand/NLDesignProtein/sharepoint/BioM3-data-share/data/datasets` |
| Aurora (ALCF) | `/flare/NLDesignProtein/sharepoint/BioM3-data-share/data/datasets` |

Database paths are resolved in this order:

1. Explicit CLI flags (`--swissprot`, `--pfam`)
2. Environment variable `BIOM3_DATABASES_ROOT`
3. Config file `configs/dbio_config.json` in BioM3-dev

For workspace use, pass paths explicitly or symlink via `./scripts/sync_databases.sh`.

## Output format

`biom3_build_dataset` writes the following files to the output directory:

| File | Description |
|------|-------------|
| `dataset.csv` | Final dataset with 4 columns (see below) |
| `dataset_annotations.csv` | Intermediate CSV with all `annot_*` columns preserved |
| `build_manifest.json` | Reproducibility manifest: biom3 version, git hash, CLI args, row counts |
| `pfam_ids.csv` | Pfam IDs used for extraction |
| `build.log` | Full build log |

### `dataset.csv` columns

| Column | Description |
|--------|-------------|
| `primary_Accession` | UniProt protein accession (e.g. `P12345`) |
| `protein_sequence` | Full amino acid sequence |
| `[final]text_caption` | Text description in BioM3 ALL-CAPS field label format |
| `pfam_label` | Pfam family identifier(s) (e.g. `PF00018`) |

### Caption format

Captions use the BioM3 ALL-CAPS format, e.g.:

```
FAMILY NAME: SH3 domain. PROTEIN NAME: Tyrosine-protein kinase Fyn. FUNCTION: Non-receptor tyrosine kinase...
```

SwissProt entries come with curated captions. Pfam entries have minimal captions by default — use enrichment (see below) for richer training signal.

## Enrichment options

By default, Pfam captions contain only family name and description. The `--enrich-pfam` flag populates up to 18 annotation fields (protein name, function, catalytic activity, GO terms, lineage, etc.) from external sources. Three enrichment methods are available, checked in priority order:

### 1. Annotation cache (fastest — recommended for repeated builds)

Pre-built Parquet files with one row per annotated UniProt entry. Lookups are instant via PyArrow predicate pushdown.

```bash
./pipeline/0100_build_dataset.sh data/SH3/ --pfam-ids PF00018 \
    --enrich-pfam \
    --annotation-cache data/databases/trembl/trembl_annotations.parquet
```

Multiple caches can be passed (e.g. Swiss-Prot + TrEMBL):

```bash
--annotation-cache data/databases/swissprot/swissprot_annotations.parquet \
                   data/databases/trembl/trembl_annotations.parquet
```

Build a cache once with `biom3_build_annotation_cache` (see [Performance optimization](#performance-optimization)).

### 2. Local `.dat` files (offline, no pre-build needed)

Parses UniProt flat files directly. Slower than caches but requires no preprocessing.

```bash
./pipeline/0100_build_dataset.sh data/SH3/ --pfam-ids PF00018 \
    --enrich-pfam \
    --uniprot-dat ../BioM3-data-share/databases/swissprot/uniprot_sprot.dat.gz \
                  ../BioM3-data-share/databases/trembl/uniprot_trembl.dat.gz
```

**Note**: Pfam accessions are overwhelmingly from TrEMBL (unreviewed UniProt). Using only `uniprot_sprot.dat.gz` will match very few Pfam entries. For full coverage, include the TrEMBL file as well — though be aware that `uniprot_trembl.dat.gz` (~161 GB) takes hours to parse.

### 3. UniProt REST API (fallback)

If neither cache nor `.dat` files are provided, `--enrich-pfam` fetches annotations from the UniProt REST API with disk caching and rate limiting:

```bash
./pipeline/0100_build_dataset.sh data/SH3/ --pfam-ids PF00018 --enrich-pfam
```

API responses are cached in `--uniprot-cache-dir` (default: `.uniprot_cache/`) for subsequent runs. This is the slowest method and requires internet access.

## Taxonomy

Add NCBI taxonomy lineage and optionally filter by taxonomic rank:

```bash
./pipeline/0100_build_dataset.sh data/SH3/ --pfam-ids PF00018 \
    --add-taxonomy \
    --taxonomy-filter "superkingdom=Bacteria" \
    --taxid-index data/databases/ncbi_taxonomy/accession2taxid.sqlite
```

| Flag | Description |
|------|-------------|
| `--add-taxonomy` | Add `annot_lineage` column from NCBI taxonomy files |
| `--taxonomy-filter` | Keep only entries matching a taxonomic rank (e.g. `superkingdom=Bacteria`, `phylum=Pseudomonadota`) |
| `--taxid-index` | Path to pre-built SQLite index for fast accession-to-taxid lookups |

Taxonomy requires the `ncbi_taxonomy/` database directory (synced from BioM3-data-share). The `--taxid-index` flag is strongly recommended — without it, lookups stream the 11 GB `prot.accession2taxid.gz` file (~10-15 min per build).

## Performance optimization

Three one-time preprocessing steps dramatically speed up repeated dataset builds:

### Convert source CSVs to Parquet

The 35 GB Pfam CSV can be converted to ~5-8 GB Parquet for 5-10x faster queries. If a `.parquet` file exists alongside the `.csv`, readers auto-detect and use it.

```bash
biom3_convert_to_parquet ../BioM3-data-share/data/datasets/Pfam_protein_text_dataset.csv
biom3_convert_to_parquet ../BioM3-data-share/data/datasets/fully_annotated_swiss_prot.csv
```

### Build annotation cache

Parse TrEMBL's 161 GB `.dat.gz` once into a compact Parquet cache. All subsequent `--enrich-pfam` runs use instant lookups.

```bash
biom3_build_annotation_cache \
    --dat ../BioM3-data-share/databases/trembl/uniprot_trembl.dat.gz \
    -o data/databases/trembl/trembl_annotations.parquet

biom3_build_annotation_cache \
    --dat ../BioM3-data-share/databases/swissprot/uniprot_sprot.dat.gz \
    -o data/databases/swissprot/swissprot_annotations.parquet
```

### Build taxonomy SQLite index

Index the 1.55B-row accession-to-taxid mapping for instant lookups (seconds instead of 10-15 min):

```bash
biom3_build_taxid_index \
    ../BioM3-data-share/databases/ncbi_taxonomy/prot.accession2taxid.gz \
    -o data/databases/ncbi_taxonomy/accession2taxid.sqlite
```

## CLI reference

| Argument | Default | Description |
|----------|---------|-------------|
| `--pfam-ids ID...` | *(required)* | One or more Pfam family IDs (e.g. `PF00018 PF07714`) |
| `--swissprot PATH` | from config | Path to `fully_annotated_swiss_prot.csv` |
| `--pfam PATH` | from config | Path to `Pfam_protein_text_dataset.csv` |
| `--databases-root PATH` | from config | Override database root path |
| `--config PATH` | `configs/dbio_config.json` | Path to dbio config JSON |
| `--chunk-size N` | `500000` | Chunk size for Pfam CSV reading |
| `--enrich-pfam` | off | Enrich Pfam captions with UniProt annotations |
| `--annotation-cache PATH...` | none | Pre-built annotation Parquet cache(s) |
| `--uniprot-dat PATH...` | none | Local UniProt `.dat.gz` file(s) for offline enrichment |
| `--uniprot-cache-dir DIR` | `.uniprot_cache` | Cache directory for REST API responses |
| `--uniprot-batch-size N` | `100` | Batch size for UniProt API requests |
| `--add-taxonomy` | off | Add NCBI taxonomy lineage |
| `--taxonomy-filter EXPR...` | none | Filter by rank (e.g. `"superkingdom=Bacteria"`) |
| `--taxid-index PATH` | none | Pre-built SQLite accession-to-taxid index |

## TOML configuration

When running through `run_pipeline.py`, Step 100 options are set in the `[build_dataset]` section:

```toml
[build_dataset]
pfam_ids = ["PF00018"]
swissprot = "../BioM3-data-share/data/datasets/fully_annotated_swiss_prot.csv"
pfam      = "../BioM3-data-share/data/datasets/Pfam_protein_text_dataset.csv"
enrich_pfam = true
annotation_cache = ["data/databases/trembl/trembl_annotations.parquet"]
```

When using Step 100, set `training_csv` in `[paths]` to `data/<FAMILY>/dataset.csv` — this matches the hardcoded output filename from `biom3_build_dataset`. The output directory is derived from the parent of `training_csv`.

See `configs/pipelines/_template.toml` for the full set of available options.

## Connection to Step 200

The output `dataset.csv` feeds directly into Step 200 (Embedding), which encodes sequences and text captions into joint embeddings via PenCL and Facilitator:

```
Step 100: dataset.csv (sequences + text)
  → Step 200: PenCL + Facilitator → compiled_emb.hdf5
    → Step 300: ProteoScribe finetuning
      → Step 400: Sequence generation
```

## Examples

### Basic extraction

```bash
./pipeline/0100_build_dataset.sh data/SH3/ --pfam-ids PF00018
```

### Multiple families

```bash
./pipeline/0100_build_dataset.sh data/SH3_kinase/ --pfam-ids PF00018 PF07714
```

### Explicit database paths

```bash
./pipeline/0100_build_dataset.sh data/SH3/ --pfam-ids PF00018 \
    --swissprot ../BioM3-data-share/data/datasets/fully_annotated_swiss_prot.csv \
    --pfam ../BioM3-data-share/data/datasets/Pfam_protein_text_dataset.csv
```

### Enriched with annotation cache

```bash
./pipeline/0100_build_dataset.sh data/SH3/ --pfam-ids PF00018 \
    --enrich-pfam \
    --annotation-cache data/databases/swissprot/swissprot_annotations.parquet \
                       data/databases/trembl/trembl_annotations.parquet
```

### Enriched with taxonomy filtering

```bash
./pipeline/0100_build_dataset.sh data/SH3/ --pfam-ids PF00018 \
    --enrich-pfam \
    --add-taxonomy \
    --taxonomy-filter "superkingdom=Bacteria" \
    --taxid-index data/databases/ncbi_taxonomy/accession2taxid.sqlite
```

### Via pipeline runner

```bash
python run_pipeline.py configs/pipelines/SH3.toml --steps 100
python run_pipeline.py configs/pipelines/SH3.toml --dry-run  # preview args
```
