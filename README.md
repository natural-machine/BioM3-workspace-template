# Project Name

## About

<!-- Describe your research project: protein family, goals, key findings. -->

## Setup

### Install BioM3

```bash
conda create -n biom3-env python=3.12
conda activate biom3-env
python -m pip install torch==2.8 torchvision --index-url https://download.pytorch.org/whl/cu129
python -m pip install -r requirements/<machine>.txt   # spark, polaris, or aurora
python -m pip install git+https://github.com/addison-nm/BioM3-dev.git@v0.1.0a1
```

Source the environment before running pipeline steps:

```bash
source environment.sh
```

### Symlink weights

Pretrained model weights are stored in [BioM3-data-share](https://github.com/natural-machine/BioM3-data-share). Symlink them into your workspace:

```bash
./scripts/sync_weights.sh <weights_source> weights
```

| Machine | Weights path |
|---------|-------------|
| DGX Spark | `/data/data-share/BioM3-data-share/data/weights` |
| Polaris (ALCF) | `/grand/NLDesignProtein/sharepoint/BioM3-data-share/data/weights` |
| Aurora (ALCF) | `/flare/NLDesignProtein/sharepoint/BioM3-data-share/data/weights` |

### Symlink databases (optional)

For local BLAST searches, symlink reference databases:

```bash
./scripts/sync_databases.sh <databases_source> data/databases
```

| Machine | Databases path |
|---------|---------------|
| DGX Spark | `/data/data-share/BioM3-data-share/databases` |
| Polaris (ALCF) | `/grand/NLDesignProtein/sharepoint/BioM3-data-share/databases` |
| Aurora (ALCF) | `/flare/NLDesignProtein/sharepoint/BioM3-data-share/databases` |

### Build a dataset (optional)

To build a training dataset from reference databases instead of providing your own CSV:

```bash
./pipeline/0100_build_dataset.sh data/MyFamily/ --pfam-ids PF00018 \
    --swissprot ../BioM3-data-share/data/datasets/fully_annotated_swiss_prot.csv \
    --pfam ../BioM3-data-share/data/datasets/Pfam_protein_text_dataset.csv
```

This extracts sequences matching the Pfam family from SwissProt and Pfam databases, producing a 4-column `dataset.csv`. Database and training data paths are configured in [`configs/dbio_config.json`](configs/dbio_config.json) and can be overridden with CLI flags. Optional flags add UniProt annotation enrichment (`--enrich-pfam`) and NCBI taxonomy lineage (`--add-taxonomy`). For one-time performance optimization (Parquet conversion, annotation caching, taxonomy indexing), see [docs/0100_build_dataset.md](docs/0100_build_dataset.md).

### Add your data

**Option A**: Build from reference databases using Step 100 (see above). Set `training_csv = "data/<FamilyName>/dataset.csv"` in your TOML config (matching `biom3_build_dataset`'s output filename).

**Option B**: Place your own CSV under `data/<FamilyName>/`. CSVs should contain columns: `protein_sequence`, `primary_Accession`, and a text description column.

See [QUICKSTART.md](QUICKSTART.md) for detailed instructions on data format, pipeline configuration, and running the pipeline.

## References

[1] Natural Language Prompts Guide the Design of Novel Functional Protein Sequences. Niksa Praljak, Hugh Yeh, Miranda Moore, Michael Socolich, Rama Ranganathan, Andrew L. Ferguson. bioRxiv 2024.11.11.622734; doi: [10.1101/2024.11.11.622734](https://doi.org/10.1101/2024.11.11.622734)
