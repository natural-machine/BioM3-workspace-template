# Pipeline Improvements and Step Renumbering

**Date:** 2026-04-06
**Pre-session state:** `git checkout df1394f`

## Summary

Major overhaul of the pipeline runner and step scripts: fixed inference seed, soft-coded hardcoded arguments across pipeline scripts, added multi-variant pipeline support with automatic fan-out, added a `--dry-run` output tree, created a new Step 100 (build dataset), and renumbered all steps from 2-digit to 4-digit IDs (100, 200, ..., 900) for future extensibility.

## Changes

### 1. Seed fix
- `configs/inference/stage3_ProteoScribe_sample.json`: changed `seed` from `42` to `0` to match `finetune.json`.

### 2. Soft-coded pipeline script arguments
Previously, `0200_embedding.sh` and `0400_generate.sh` had hardcoded model weight paths, config paths, batch size, device, and dataset key. Now all three embedding/finetuning/generation scripts accept `--key value` flag overrides with sensible defaults:

- **`0200_embedding.sh`**: Added `--pencl_weights`, `--facilitator_weights`, `--pencl_config`, `--facilitator_config`, `--batch_size`, `--dataset_key`, `--device`, and `--` passthrough.
- **`0400_generate.sh`**: Same flags plus `--proteoscribe_config` and `--` passthrough.
- **`0300_finetune.sh`**: Added `--device` flag.

`run_pipeline.py` was updated to read new TOML sections (`[embedding]`, extended `[finetuning]`/`[generation]`) and pass these flags through via `build_step_args()`. Generic `extra_args` passthrough supported via `--` separator.

### 3. Multi-variant pipeline support
Added support for running a step with multiple configurations via TOML array-of-tables:

```toml
[[generation]]
variant = "random"
unmasking_order = "random"

[[generation]]
variant = "confidence"
unmasking_order = "confidence"
```

Key design decisions:
- Each variant gets auto-derived output dirs (e.g., `generation_random/`, `samples_random/`).
- Downstream steps automatically fan out (one run per upstream variant).
- Fan-out uses **replacement** semantics (not multiplicative) to avoid exponential growth.
- Any step section can set `fan_out = false` to collapse back to a single run.
- Variant filter from CLI: `--steps 400.random 500 600`.
- Backward compatible: single `[section]` configs work unchanged.

New functions in `run_pipeline.py`: `get_step_variants()`, `parse_step_spec()`, `derive_variant_paths()`, `validate_variants()`.

### 4. Dry-run output tree
`--dry-run` now prints an expected output tree at the end, showing all files and directories the pipeline would produce. Implemented via `get_step_outputs()`, `_build_tree()`, `_render_tree()`, `print_output_tree()`.

### 5. Step renumbering
Renumbered all pipeline steps from sequential 1-9 to 4-digit IDs (100-900) with 4-digit file prefixes:

| Step ID | Script | Name |
|---------|--------|------|
| 100 | `0100_build_dataset.sh` | Build Dataset (new) |
| 200 | `0200_embedding.sh` | Embedding |
| 300 | `0300_finetune.sh` | Finetuning |
| 400 | `0400_generate.sh` | Generation |
| 500 | `0500_colabfold.sh` | ColabFold |
| 600 | `0600_blast_search.sh` | BLAST Search |
| 610 | `0610_fetch_hit_structures.sh` | Fetch Reference Structures |
| 700 | `0700_compare_structures.sh` | Structure Comparison |
| 800 | `0800_plot_results.sh` | Plot Results |
| 900 | `0900_webapp.sh` | Web App |

The 4-digit convention leaves room for inserting steps between existing ones (e.g., 150 between 100 and 200, or 610/620 for sub-steps).

### 6. New Step 100: Build Dataset
Created `0100_build_dataset.sh` as a thin wrapper around `biom3_build_dataset` with passthrough args. Integrated into `run_pipeline.py` and `_template.toml`.

### 7. Documentation fixes
- `docs/biom3_ecosystem.md`: Removed "*(Planned)*" label for workspace-template, updated version reference from v0.0.1 to v0.1.0a1.
- `QUICKSTART.md`: Updated with all new step numbers, new `[embedding]`/`[build_dataset]` config sections, multi-variant documentation, `--dry-run` output tree description, and 4-digit script filenames.
- `CLAUDE.md`: Updated repository layout and example commands.
- `_template.toml`: Full rewrite with new step IDs, `# --- ` comment convention for descriptions vs toggles, and `[build_dataset]` section.

## Files modified
- `configs/inference/stage3_ProteoScribe_sample.json`
- `configs/pipelines/_template.toml`
- `run_pipeline.py`
- `pipeline/0100_build_dataset.sh` (new)
- `pipeline/0200_embedding.sh` (renamed from `01_embedding.sh`)
- `pipeline/0300_finetune.sh` (renamed from `02_finetune.sh`)
- `pipeline/0400_generate.sh` (renamed from `03_generate.sh`)
- `pipeline/0500_colabfold.sh` (renamed from `04_colabfold.sh`)
- `pipeline/0600_blast_search.sh` (renamed from `05_blast_search.sh`)
- `pipeline/0610_fetch_hit_structures.sh` (renamed from `05b_fetch_hit_structures.sh`)
- `pipeline/0700_compare_structures.sh` (renamed from `06_compare_structures.sh`)
- `pipeline/0800_plot_results.sh` (renamed from `07_plot_results.sh`)
- `pipeline/0900_webapp.sh` (renamed from `08_webapp.sh`)
- `QUICKSTART.md`
- `CLAUDE.md`
- `docs/biom3_ecosystem.md`

## Deferred / not implemented
- **`SYNC_LOG.md`** is still empty. Should be populated with the initial sync point (BioM3-dev commit for `v0.1.0a1`).
- **`biom3_build_dataset` CLI interface** is not fully known from this repo. `0100_build_dataset.sh` is a skeleton that passes all args through; it will need refinement once the CLI is finalized in BioM3-dev.
