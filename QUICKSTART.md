# Quickstart Guide

How to create a new research workspace from the BioM3 workspace template and run the protein generation pipeline. The BioM3-workspace-template is part of the [BioM3 ecosystem](docs/biom3_ecosystem.md). See that document for cross-repo workflows, shared data architecture, and version compatibility details.

## Table of contents

- [Create your workspace](#create-your-workspace)
- [Prerequisites](#prerequisites)
- [Install BioM3](#install-biom3)
- [Set up weights and databases](#set-up-weights-and-databases)
- [Prepare your input data](#prepare-your-input-data)
- [Configure a pipeline run](#configure-a-pipeline-run)
  - [TOML config structure](#toml-config-structure)
- [Pipeline overview](#pipeline-overview)
- [Run the pipeline](#run-the-pipeline)
  - [Full pipeline](#full-pipeline)
  - [Initial phase (embedding + finetuning)](#initial-phase-embedding--finetuning)
  - [Analysis phase (structure prediction + evaluation)](#analysis-phase-structure-prediction--evaluation)
  - [Individual steps](#individual-steps)
- [Output structure](#output-structure)
- [References](#references)

---

## Create your workspace

For collaborative consistency, all BioM3 workspaces should live inside a shared `BioM3-ecosystem/` directory. Symlink `BioM3-data-share` into this directory so that all workspaces can reference weights, databases, and datasets via the same relative paths. The resulting layout should look like:

```
BioM3-ecosystem/
├── BioM3-dev/                  # core library (cloned, optional)
├── BioM3-data-share/           # symlink to shared data on this machine (--> /path/to/shared/BioM3-data-share)
├── BioM3-workflow-demo/        # reference demo (optional)
├── my-first-workspace/         # your workspace (from template)
└── my-second-workspace/        # another workspace (from template)
```

To set this up:

```bash
mkdir -p BioM3-ecosystem && cd BioM3-ecosystem

# Symlink BioM3-data-share to the shared location on your machine
ln -s /data/data-share/BioM3-data-share BioM3-data-share   # DGX Spark example

# Clone the core library
git clone https://github.com/addison-nm/BioM3-dev.git
```

Then create your workspace from the template. Click **"Use this template"** on the [GitHub repository](https://github.com/natural-machine/BioM3-workspace-template), or clone directly:

```bash
git clone https://github.com/natural-machine/BioM3-workspace-template.git my-workspace
cd my-workspace
rm -rf .git && git init   # start fresh history
```

After creating your workspace, update the `README.md` with a description of your project.

## Prerequisites

- Python 3.10+
- An NVIDIA GPU with CUDA support (tested on DGX Spark)
- Access to pretrained model weights via [BioM3-data-share](https://github.com/natural-machine/BioM3-data-share)
- [ColabFold](https://github.com/sokrypton/ColabFold) (for Step 4, structure prediction)
- [BLAST+](https://blast.ncbi.nlm.nih.gov/doc/blast-help/downloadblastdata.html) (for Step 5, homology search)
- [TMalign](https://zhanggroup.org/TM-align/) (for Step 6, structure comparison)

## Install BioM3

Create a conda environment and install the BioM3 core library:

```bash
conda create -n biom3-env python=3.12
conda activate biom3-env
python -m pip install torch==2.8 torchvision --index-url https://download.pytorch.org/whl/cu129
python -m pip install -r requirements/<machine>.txt
python -m pip install git+https://github.com/addison-nm/BioM3-dev.git@v0.1.0a1
```

Machine-specific requirements files pin versions tested on each platform:

| File | Machine |
|------|---------|
| `requirements/spark.txt` | DGX Spark |
| `requirements/polaris.txt` | Polaris (ALCF) |
| `requirements/aurora.txt` | Aurora (ALCF) |

For the web app (Step 8), install with app extras:

```bash
python -m pip install "biom3[app] @ git+https://github.com/addison-nm/BioM3-dev.git@v0.1.0a1"
```

Steps 4 and 5 require separate environments. Install them according to their respective documentation:

| Environment | Used by | Install guide |
|-------------|---------|---------------|
| `biom3-env` | Steps 1-3, 6-8 | Above |
| `colabfold` | Step 4 | [ColabFold](https://github.com/sokrypton/ColabFold) |
| `blast-env` | Step 5 | [BLAST+](https://blast.ncbi.nlm.nih.gov/doc/blast-help/downloadblastdata.html) |

Source the environment file before running any pipeline steps:

```bash
source environment.sh
```

This exports `BIOM3_WORKSPACE_VERSION` and sets machine-specific variables (auto-detected from hostname).

## Set up weights and databases (optional)

Pretrained model weights and reference databases can live in a shared [BioM3-data-share](https://github.com/natural-machine/BioM3-data-share) directory. Use the sync scripts to symlink them into your workspace.

### Shared data paths

| Machine | Weights | Databases | Datasets |
|---------|---------|-----------|----------|
| DGX Spark | `/data/data-share/BioM3-data-share/data/weights` | `/data/data-share/BioM3-data-share/databases` | `/data/data-share/BioM3-data-share/data/datasets` |
| Polaris (ALCF) | `/grand/NLDesignProtein/sharepoint/BioM3-data-share/data/weights` | `/grand/NLDesignProtein/sharepoint/BioM3-data-share/databases` | `/grand/NLDesignProtein/sharepoint/BioM3-data-share/data/datasets` |
| Aurora (ALCF) | `/flare/NLDesignProtein/sharepoint/BioM3-data-share/data/weights` | `/flare/NLDesignProtein/sharepoint/BioM3-data-share/databases` | `/flare/NLDesignProtein/sharepoint/BioM3-data-share/data/datasets` |

### Sync weights

```bash
# Preview what will be linked
./scripts/sync_weights.sh <weights_source> weights --dry-run

# Apply symlinks
./scripts/sync_weights.sh <weights_source> weights
```

Replace `<weights_source>` with the weights path for your machine from the table above, or a path to your own directory containing weights.

### Sync databases

```bash
./scripts/sync_databases.sh <databases_source> data/databases --dry-run
./scripts/sync_databases.sh <databases_source> data/databases
```

## Prepare your input data

Place input datasets in the `data` directory, for example under `data/datasets/<FamilyName>/`:

```
data/
  datasets/
    MyFamily/
      MyFamily_dataset.csv      # raw finetuning data (Steps 1-2)
      MyFamily_prompts.csv      # generation prompts (Step 3)
```

### Required CSV columns

| Column | Description |
|--------|-------------|
| `primary_Accession` | Accession number or sequence label (e.g. UniProt accession) |
| `protein_sequence` | Amino acid sequence |
| `[final]text_caption` | Text description |
| `pfam_label` | Pfam family identifier(s) (e.g. `PF00018`) |

The training dataset (`_dataset.csv`) is used in Steps 1-2 to embed sequences and finetune the model. The prompts file (`_prompts.csv`) is used in Step 3 to condition sequence generation — it has the same column format.

### Example rows

**Note the inclusion of quotes around the text field, to account for commas!**

```csv
primary_Accession,protein_sequence,[final]text_caption,pfam_label
P12345,MAEGEITTFTALTEKF...,"SH3 domain of human ABL1 tyrosine kinase",PF00018
Q67890,MKKYTCTVCGYIYNPE...,"Zinc finger protein involved in transcription regulation",PF00096
```

## Configure a pipeline run

Copy the pipeline template and replace the `<FAMILY>` placeholders:

```bash
cp configs/pipelines/_template.toml configs/pipelines/MyFamily.toml
```

Edit the new file to set your family name, paths, and any parameter overrides.

### TOML config structure

The pipeline config has these sections:

#### `[pipeline]` — Which steps to run

```toml
[pipeline]
steps = [1, 2, 3, 4, 5, "5b", 6, 7]    # full pipeline
# steps = [4, 5, "5b", 6, 7]            # analysis only (requires prior Step 3 output)
```

#### `[environments]` — Conda/venv environment names

```toml
[environments]
biom3     = "biom3-env"       # Steps 1-3, 6-8
colabfold = "colabfold"       # Step 4
blast     = "blast-env"       # Step 5
```

#### `[paths]` — Input/output locations

```toml
[paths]
output_dir  = "outputs/MyFamily"
input_csv   = "data/MyFamily/MyFamily_dataset.csv"
prompts_csv = "data/MyFamily/MyFamily_prompts.csv"
epochs      = 50

# Optional overrides (auto-detected if omitted):
# model_weights = "outputs/MyFamily/finetuning/checkpoints/<run_id>/state_dict.best.pth"
```

`input_csv` is used by Steps 1-2. `prompts_csv` is used by Step 3. All intermediate paths (HDF5, FASTA, results CSVs) are derived automatically from `output_dir` and the input file prefixes.

#### `[finetuning]` — Step 2 training config

```toml
[finetuning]
config = "configs/stage3_training/finetune.json"
```

The JSON config controls all training hyperparameters: learning rate, batch size, epochs, precision, early stopping, etc. Key parameters in `finetune.json`:

| Parameter | Default | Description |
|-----------|---------|-------------|
| `pretrained_weights` | `weights/ProteoScribe/ProteoScribe_epoch200.pth` | Base model to finetune |
| `finetune_last_n_blocks` | 1 | Transformer blocks to unfreeze |
| `lr` | 1e-4 | Learning rate |
| `epochs` | 20 | Max training epochs (overridden by TOML `paths.epochs`) |
| `batch_size` | 32 | Training batch size |
| `precision` | `"bf16"` | Mixed precision mode |
| `valid_size` | 0.2 | Validation split fraction |
| `early_stopping_patience` | 10 | Epochs before early stopping |

#### `[generation]` — Step 3 sampling options

```toml
[generation]
unmasking_order = "random"              # random | confidence | confidence_no_pad
token_strategy  = "sample"              # sample | argmax
# animate_prompts = [0, 1, 2]           # prompt indices to animate
# store_probabilities = true            # save per-step probability distributions
```

The number of replicas per prompt and other model-level sampling parameters are set in `configs/inference/stage3_ProteoScribe_sample.json`.

#### `[blast]` — Step 5 search options

```toml
[blast]
db      = "swissprot"        # swissprot | pdbaa | nr | /path/to/local/db
threads = 16
# remote = true              # force remote NCBI search
# local  = true              # force local search
# max_targets = 5
```

#### `[fetch_structures]` — Step 5b options

```toml
# [fetch_structures]
# swissprot_dat = "/path/to/uniprot_sprot.dat.gz"
# alphafold_only = true
# experimental_only = true
```

#### `[webapp]` — Step 8 options

```toml
# [webapp]
# port = 8501
```

## Pipeline overview

Broadly, the BioM3 pipeline has two phases: an **initial phase** (Steps 1-3) that embeds, finetunes, and generates sequences, and an **analysis phase** (Steps 4-7) that predicts structures and evaluates results.

| Step | Name | Description | Input | Output | Env |
|------|------|-------------|-------|--------|-----|
| 1 | Embedding | PenCL + Facilitator encode sequences and text into joint embeddings, compiled to HDF5 | CSV (sequences + text) | `.hdf5` compiled embeddings | biom3-env |
| 2 | Finetuning | Finetune pretrained ProteoScribe on family-specific embeddings | `.hdf5` from Step 1 | Model checkpoints (`.pth`) | biom3-env |
| 3 | Generation | Sample novel protein sequences from text prompts using finetuned model | Model weights + prompts CSV | `.pt` output + FASTA files | biom3-env |
| 4 | ColabFold | Predict 3D structures for generated sequences with AlphaFold2 | Per-prompt FASTA files | PDB files + `colabfold_results.csv` | colabfold |
| 5 | BLAST | Search generated sequences against protein databases for homologs | Merged FASTA | `blast_hit_results.tsv` | blast-env |
| 5b | Fetch structures | Download reference PDB structures for BLAST hits (experimental + AlphaFold) | BLAST TSV | Reference PDB files + manifest | biom3-env |
| 6 | Compare structures | Structural alignment of generated vs. reference structures with TMalign | ColabFold CSV + BLAST TSV + PDBs | `results.csv` (TM-score, RMSD, seq ID) | biom3-env |
| 7 | Plot results | Generate strip plots for TM-score, RMSD, sequence identity, pLDDT | Comparison CSV | PNG plots | biom3-env |
| 8 | Web app | Interactive Streamlit app for browsing structures, alignments, and BLAST | Pipeline outputs | HTTP server (localhost) | biom3-env |

## Run the pipeline

### Full pipeline

Run all steps in sequence using `run_pipeline.py`:

```bash
source environment.sh
python run_pipeline.py configs/pipelines/MyFamily.toml
```

Preview what will run without executing:

```bash
python run_pipeline.py configs/pipelines/MyFamily.toml --dry-run
```

The pipeline runner handles conda environment activation for each step automatically.

### Initial phase (embedding + finetuning)

Steps 1-3 train a family-specific model and generate sequences:

```bash
python run_pipeline.py configs/pipelines/MyFamily.toml --steps 1 2 3
```

Or run individual scripts:

```bash
# Step 1: Embed training data
./pipeline/01_embedding.sh data/MyFamily/MyFamily_dataset.csv outputs/MyFamily/embeddings

# Step 2: Finetune ProteoScribe
./pipeline/02_finetune.sh outputs/MyFamily/embeddings/MyFamily_dataset.compiled_emb.hdf5 outputs/MyFamily/finetuning 50

# Step 3: Generate sequences from prompts
./pipeline/03_generate.sh \
    outputs/MyFamily/finetuning/checkpoints/<run_id>/state_dict.best.pth \
    data/MyFamily/MyFamily_prompts.csv \
    outputs/MyFamily/generation \
    --fasta --fasta_merge --fasta_dir outputs/MyFamily/samples
```

### Analysis phase (structure prediction + evaluation)

Steps 4-7 evaluate the generated sequences. These require FASTA output from Step 3:

```bash
python run_pipeline.py configs/pipelines/MyFamily.toml --steps 4 5 5b 6 7
```

Or run individual scripts:

```bash
# Step 4: Predict structures with ColabFold
conda activate colabfold
./pipeline/04_colabfold.sh outputs/MyFamily/samples outputs/MyFamily/structures

# Step 5: BLAST search
conda activate blast-env
./pipeline/05_blast_search.sh outputs/MyFamily/samples/all_sequences.fasta outputs/MyFamily/blast

# Step 5b: Fetch reference structures for BLAST hits
conda activate biom3-env
./pipeline/05b_fetch_hit_structures.sh outputs/MyFamily/blast/blast_hit_results.tsv outputs/MyFamily/blast

# Step 6: Compare structures (TMalign)
./pipeline/06_compare_structures.sh \
    outputs/MyFamily/structures/colabfold_results.csv \
    outputs/MyFamily/blast/blast_hit_results.tsv \
    outputs/MyFamily/structures \
    outputs/MyFamily/blast/reference_structures \
    outputs/MyFamily/comparison

# Step 7: Plot results
./pipeline/07_plot_results.sh \
    outputs/MyFamily/comparison/results.csv \
    outputs/MyFamily/images \
    --colabfold-csv outputs/MyFamily/structures/colabfold_results.csv
```

### Individual steps

Run any step directly with its shell script. Each script prints usage when called without arguments:

```bash
./pipeline/01_embedding.sh
# Usage: ./pipeline/01_embedding.sh <input_csv> <output_dir>
```

### Web app

Step 8 launches an interactive Streamlit app (not included in the default pipeline order):

```bash
python run_pipeline.py configs/pipelines/MyFamily.toml --steps 8
# or
./pipeline/08_webapp.sh --port 8501
```

## Output structure

All outputs are written under the `output_dir` specified in the TOML config. Here is the full directory tree after a complete pipeline run:

```
outputs/MyFamily/
├── embeddings/                         # Step 1
│   ├── <prefix>.PenCL_emb.pt          # Stage 1 embeddings (z_t, z_p tensors)
│   ├── <prefix>.Facilitator_emb.pt    # Stage 2 embeddings (z_c tensor)
│   ├── <prefix>.compiled_emb.hdf5     # Compiled HDF5 for finetuning
│   ├── build_manifest.json
│   └── run.log
│
├── finetuning/                         # Step 2
│   ├── checkpoints/
│   │   └── <run_id>/
│   │       ├── state_dict.best.pth    # Best model weights (used by Step 3)
│   │       └── *.ckpt                 # Intermediate checkpoints
│   └── runs/
│       └── <run_id>/                  # Training logs and metrics
│
├── generation/                         # Step 3
│   ├── <prefix>.ProteoScribe_output.pt   # Raw generated sequences
│   ├── embeddings/                       # Prompt embeddings (intermediate)
│   ├── animations/                       # GIFs (if --animate_prompts)
│   └── probabilities/                    # .npz files (if --store_probabilities)
│
├── samples/                            # Step 3 (FASTA output)
│   ├── all_sequences.fasta            # Merged FASTA for Steps 4-5
│   ├── <prefix>_prompt_0_samples.fasta
│   ├── <prefix>_prompt_1_samples.fasta
│   └── ...
│
├── structures/                         # Step 4
│   ├── colabfold_results.csv          # Summary: structure, pLDDT, pTM, pdbfilename
│   └── prompt_<i>/                    # Per-prompt ColabFold output
│       ├── *.pdb                      # Predicted structures
│       └── log.txt
│
├── blast/                              # Steps 5 + 5b
│   ├── blast_hit_results.tsv          # BLAST hits (qseqid, sseqid, pident, evalue, ...)
│   ├── structure_manifest.tsv         # Accession, source, PDB ID, resolution (Step 5b)
│   └── reference_structures/          # Downloaded reference PDBs
│       └── <accession>.pdb
│
├── comparison/                         # Step 6
│   ├── results.csv                    # TM-score, RMSD, seq_id per query-reference pair
│   └── logs/
│       └── *_v_*.TMalign.log          # Individual TMalign output logs
│
└── images/                             # Step 7
    ├── TM_scores.png
    ├── RMSD_scores.png
    ├── seqID_scores.png
    └── pLDDT_scores.png               # (if ColabFold CSV provided)
```

### Key file formats

| File | Format | Contents |
|------|--------|----------|
| `.compiled_emb.hdf5` | HDF5 | Group `MMD_data` with datasets: `acc_id`, `sequence`, `sequence_length`, `text_to_protein_embedding` |
| `state_dict.best.pth` | PyTorch state dict | Finetuned ProteoScribe model weights |
| `.ProteoScribe_output.pt` | PyTorch dict | Keys `prompt_<i>` (list of generated sequences per prompt) + `_metadata` |
| `colabfold_results.csv` | CSV | Columns: `structure`, `pLDDT`, `pTM`, `pdbfilename` |
| `blast_hit_results.tsv` | TSV | Columns: `qseqid`, `sseqid`, `stitle`, `pident`, `length`, `evalue`, `bitscore` |
| `results.csv` | CSV | Columns: `query_id`, `pdbid`, `chain`, `TM`, `q_length`, `r_length`, `aligned_length`, `RMSD`, `seq_id` |
| `build_manifest.json` | JSON | Execution metadata: BioM3 version, git hash, timestamp, CLI args, resolved paths |

## References

[1] Natural Language Prompts Guide the Design of Novel Functional Protein Sequences. Niksa Praljak, Hugh Yeh, Miranda Moore, Michael Socolich, Rama Ranganathan, Andrew L. Ferguson. bioRxiv 2024.11.11.622734; doi: [10.1101/2024.11.11.622734](https://doi.org/10.1101/2024.11.11.622734)
