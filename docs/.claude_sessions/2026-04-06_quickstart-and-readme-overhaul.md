# Session: QUICKSTART.md and README.md overhaul

**Date:** 2026-04-06
**Pre-session state:** `git checkout cc93924`

## Summary

Created a comprehensive `QUICKSTART.md` template usage guide and replaced the existing `README.md` with a slim, user-fillable skeleton. Also renamed `BIOM3_WORKFLOW_VERSION` to `BIOM3_WORKSPACE_VERSION` across the entire repo.

## Changes

### New file: QUICKSTART.md

Full quickstart guide for researchers using the template, covering:

- Creating a new workspace from the GitHub template
- Prerequisites, installation (BioM3-dev + per-machine requirements files + ColabFold/BLAST environments)
- Setting up weights, databases, and shared datasets via sync scripts
- Input data format (all four required CSV columns: `primary_Accession`, `protein_sequence`, `[final]text_caption`, `pfam_label`)
- Complete TOML config file walkthrough (all sections)
- Pipeline overview table (Steps 1-8 with inputs, outputs, environments)
- Execution instructions for full pipeline, initial phase (Steps 1-3), analysis phase (Steps 4-7), individual steps, and web app
- Full output directory tree with key file format descriptions
- Link to `docs/biom3_ecosystem.md` for ecosystem context

### Replaced: README.md

Slimmed down from a full guide to a user-fillable skeleton:

- Empty "About" section (HTML comment placeholder)
- Setup section: install BioM3, symlink weights/databases, add data
- Pointer to QUICKSTART.md for detailed pipeline instructions
- References section with BioM3 citation

### Rename: BIOM3_WORKFLOW_VERSION -> BIOM3_WORKSPACE_VERSION

Renamed across all 12 files that referenced it:

- `environment.sh` (the export)
- All 8 pipeline scripts (`pipeline/01_embedding.sh` through `pipeline/08_webapp.sh`)
- `QUICKSTART.md`, `CLAUDE.md`

The variable is purely internal to this repo (no external consumers), so the rename was safe.

### Minor additions

- Added `pip install -r requirements/<machine>.txt` step to install instructions in both QUICKSTART.md and README.md
- Added Datasets column to the shared data paths table in QUICKSTART.md

## Files modified

- `README.md` — replaced with skeleton
- `QUICKSTART.md` — new file
- `environment.sh` — version variable rename
- `CLAUDE.md` — version variable rename
- `pipeline/01_embedding.sh` — version variable rename
- `pipeline/02_finetune.sh` — version variable rename
- `pipeline/03_generate.sh` — version variable rename
- `pipeline/04_colabfold.sh` — version variable rename
- `pipeline/05_blast_search.sh` — version variable rename
- `pipeline/05b_fetch_hit_structures.sh` — version variable rename
- `pipeline/06_compare_structures.sh` — version variable rename
- `pipeline/07_plot_results.sh` — version variable rename
- `pipeline/08_webapp.sh` — version variable rename

## Notes

- The `scripts/sync_weights.sh` and `scripts/sync_databases.sh` are nearly identical — the only difference is that `sync_databases.sh` has an extra loop for top-level files. This was noted but not refactored (out of scope).
