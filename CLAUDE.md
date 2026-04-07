# CLAUDE.md

## Practices

Store session notes in docs/.claude_sessions/

## Project overview

BioM3-workspace-template is a GitHub template repository for creating new BioM3 research workspaces. It provides the standard directory structure, sync scripts, and configuration scaffolding used by the BioM3 finetuning and sequence generation pipeline. Researchers use this as a starting point by clicking "Use this template" on GitHub or cloning directly.

## Versioning

Version is defined in the `VERSION` file at the repo root (PEP 440 format, e.g. `0.0.1a1`). This is the single source of truth — read by `run_pipeline.py` and exported as `BIOM3_WORKSPACE_VERSION` by `environment.sh`. Cross-repo compatibility with BioM3-dev is tracked in `SYNC_LOG.md`.

## Ecosystem context

BioM3-workspace-template is a workspace scaffold in the BioM3 multi-repo ecosystem. See [docs/biom3_ecosystem.md](docs/biom3_ecosystem.md) for full details.

Related repositories:
- **BioM3-dev** — core Python library (installed via pip)
- **BioM3-data-share** — shared model weights, datasets, and reference databases
- **BioM3-workflow-demo** — end-to-end demo of finetuning and generation (reference implementation)

Machine-specific repo paths are in `.claude/repo_paths.json` (gitignored, not version controlled). This file maps repo names to absolute paths on the current machine.

Version compatibility with BioM3-dev is tracked in [SYNC_LOG.md](SYNC_LOG.md).

## Repository layout

```
pipeline/           # Step scripts (0100_build_dataset.sh through 0900_webapp.sh)
scripts/            # Helper scripts (sync, setup)
configs/            # JSON model/training configs + TOML pipeline configs
requirements/       # Per-machine pip requirements (spark, polaris, aurora)
data/               # Input datasets per family (gitignored)
weights/            # Symlinked model weights from BioM3-data-share (gitignored)
outputs/            # Pipeline outputs per family (gitignored)
logs/               # Training and pipeline logs (gitignored)
docs/               # Documentation and session notes
run_pipeline.py     # Config-driven pipeline runner
environment.sh      # Environment variables (source before running)
VERSION             # Single-source version (PEP 440)
SYNC_LOG.md         # BioM3-dev compatibility tracking
```

## Building and running

Requires BioM3-dev installed (`pip install git+https://github.com/addison-nm/BioM3-dev.git@v0.1.0a2` or `pip install -e /path/to/BioM3-dev`). Source `environment.sh` before running pipeline steps.

```bash
source environment.sh
python run_pipeline.py configs/pipelines/<family>.toml   # full pipeline
./pipeline/0200_embedding.sh                              # individual step
```

Steps 5-6 require separate conda environments (colabfold, blast-env). The pipeline runner handles environment activation.

Weights and databases are symlinked from BioM3-data-share. See README.md for per-machine paths and sync instructions.

## Commit style

Use [Conventional Commits](https://www.conventionalcommits.org/):

```
<type>: <short summary>
```

Types: `feat`, `fix`, `refactor`, `test`, `docs`, `chore`

Keep the summary under 72 characters.
