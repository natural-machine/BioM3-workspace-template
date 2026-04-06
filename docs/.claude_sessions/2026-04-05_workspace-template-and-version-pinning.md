# Session: Workspace template population and version pinning

**Date:** 2026-04-05
**Scope:** Populate BioM3-workspace-template from workflow-demo structure; pin BioM3-dev version across repos

## Changes

### 1. BioM3-workspace-template — full population

Copied the generic infrastructure from BioM3-workflow-demo into BioM3-workspace-template, transforming it from a bare scaffold into a functional GitHub template repo. No demo-specific data (SH3/CM datasets, demo session notes, family-specific TOML configs) was included.

**Copied verbatim (27 files):**
- 9 pipeline scripts (`pipeline/01_embedding.sh` through `08_webapp.sh`)
- 7 helper scripts (`scripts/sync_weights.sh`, `sync_databases.sh`, `create_mini_dataset.py`, `fetch_hit_structures.py`, `make_plots.py`, `samples_to_fasta.py`, `samples_to_fasta.sh`)
- 8 config files (inference, training, app_settings — all architecture defaults)
- 3 requirements files (`requirements/{spark,polaris,aurora}.txt`)
- `environment.sh`, `run_pipeline.py`

**Created new:**
- `configs/pipelines/_template.toml` — fully commented pipeline config with `<FAMILY>` placeholders covering all sections (`[pipeline]`, `[environments]`, `[paths]`, `[finetuning]`, `[generation]`, `[blast]`, `[fetch_structures]`, `[webapp]`)
- `VERSION` (initially `0.0.1a1`, later updated to `0.1.0a1`)
- `SYNC_LOG.md` — empty table, generic "this repository" language
- `.gitkeep` files for `data/`, `data/databases/`, `data/datasets/`, `logs/`, `outputs/`, `weights/`

**Updated existing:**
- `.gitignore` — switched from `data/` (directory-level ignore) to `data/*` pattern with negation rules so `.gitkeep` files are properly tracked by git
- `CLAUDE.md` — added Versioning section, SYNC_LOG.md reference, fixed layout listing (08 not 09), added `requirements/` and `VERSION`
- `README.md` — expanded directory tree, updated Quick Start step 6 to reference `_template.toml`

**Removed:** stale `.gitkeep` from `configs/`, `pipeline/`, `scripts/` (now have real content)

### 2. Version alignment across ecosystem

Set all three repos to version `0.1.0a1`:
- **BioM3-dev**: already at `0.1.0a1` (via `src/biom3/__init__.py`, read dynamically by `pyproject.toml`)
- **BioM3-workflow-demo**: already at `0.1.0a1` (via `VERSION` file)
- **BioM3-workspace-template**: updated `VERSION` from `0.0.1a1` to `0.1.0a1`

### 3. BioM3-dev pip install pinning

Pinned `pip install` references to `@v0.1.0a1` in both workflow-demo and workspace-template so they install a specific BioM3-dev version rather than HEAD:

- `README.md` and `CLAUDE.md` in both repos: `git+https://github.com/addison-nm/BioM3-dev.git` → `git+https://github.com/addison-nm/BioM3-dev.git@v0.1.0a1`

**Note:** This requires a `v0.1.0a1` git tag on BioM3-dev (`git tag v0.1.0a1 && git push origin v0.1.0a1`).

## Final state

BioM3-workspace-template: 44 tracked files, ready for initial commit and GitHub template configuration. Researchers can now clone, copy `_template.toml`, replace `<FAMILY>` placeholders, and run the full pipeline.
