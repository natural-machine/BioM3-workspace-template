# Fan-out Refinements and Config Cleanup

**Date:** 2026-04-06 (second session)
**Pre-session state:** `git checkout 2f74a97`

## Summary

Refined the multi-variant fan-out model, reorganized TOML config sections so that step-specific parameters live under their step's section rather than `[paths]`, and fixed several bugs discovered during live testing.

## Changes

### Fan-out model changes

**Multiplicative cross-product instead of replacement.** When a step defines `[[variants]]` while there's an active fan-out from upstream, the result is now a cross-product (2 generation variants x 2 BLAST databases = 4 runs). Previously, downstream variants replaced the active context, silently losing upstream variant paths.

**Removed `fan_out = false` collapse.** Collapse had the same path-breakage problem as replacement — it reverted to base paths that don't exist when upstream steps produced variant-suffixed directories. Narrowing scope is now done via `--steps 400.random 500 600` (variant filter at the source).

**Variant expansion propagates through skipped steps.** The pipeline runner now walks all steps in `STEP_ORDER` up to the last executed step, applying variant expansion regardless of whether each step is actually run. This means `--steps 400 500 600` correctly inherits fan-out from `[[finetuning]]` variants defined in the config, even though Step 300 isn't executed. The config is the single source of truth — no manifest files or hidden state between runs.

**`[section_defaults]` convention.** Since TOML forbids both `[generation]` and `[[generation]]` in the same file, shared values for multi-variant steps are specified in `[generation_defaults]`. Each `[[generation]]` variant inherits from defaults, with variant values taking precedence. Works for any step: `[finetuning_defaults]`, `[blast_defaults]`, etc.

### Config reorganization

Moved step-specific parameters out of `[paths]` into their respective step sections:

| Parameter | From | To | Rationale |
|-----------|------|----|-----------|
| `epochs` | `[paths]` | `[finetuning]` | Finetuning hyperparameter |
| `prompts_csv` | `[paths]` | `[generation]` | Generation input, per-variant overridable |
| `model_weights` | `[paths]` | `[generation]` | Generation input, auto-detected if omitted |

`training_csv` stays in `[paths]` as a shared path connecting Steps 100 and 200, but can be overridden per `[[build_dataset]]` variant for multi-dataset fan-out.

### Multi-dataset fan-out

Each `[[build_dataset]]` variant can specify its own `training_csv` output path:

```toml
[[build_dataset]]
variant = "SH3"
pfam_ids = ["PF00018"]
training_csv = "data/SH3/SH3_dataset.csv"

[[build_dataset]]
variant = "kinase"
pfam_ids = ["PF00069"]
training_csv = "data/kinase/kinase_dataset.csv"
```

Steps 200+ fan out automatically, each using the correct `training_csv`. The `--output-filename` flag (added to BioM3-dev's `biom3_build_dataset`) is derived from the basename of `training_csv`.

### Bug fixes

- **`animate_prompts = "all"` string iteration bug.** `[str(x) for x in "all"]` produced `["a", "l", "l"]`. Fixed to pass string values as a single arg.
- **`BIOM3_WORKSPACE_VERSION` not set.** Pipeline scripts showed "workflow vunknown". Fixed by exporting the version from `run_pipeline.py` via `os.environ` before running steps.
- **`extra_args` passthrough for Step 300.** Added `--` separator support to `0300_finetune.sh` and `_append_extra_args` in `build_step_args` case "300".

### Config and documentation updates

- `configs/dbio_config.json` added (by user) — configures database and training data paths for `biom3_build_dataset`.
- `_template.toml`: simplified `[build_dataset]` section (database paths now handled by `dbio_config.json`), added `[section_defaults]` documentation, updated all sections for parameter moves.
- `test.toml`: updated to match new config structure.
- `README.md`: added `dbio_config.json` reference in "Build a dataset" section.
- `QUICKSTART.md`: user edits to install instructions (source vs pip install options).

## Files modified

- `run_pipeline.py` — fan-out logic, config reading, `get_step_variants` defaults merging, skipped-step expansion, bug fixes
- `pipeline/0300_finetune.sh` — `extra_args` passthrough
- `configs/pipelines/_template.toml` — parameter moves, simplified build_dataset, defaults convention
- `configs/pipelines/test.toml` — updated to match
- `README.md` — dbio_config reference
- `QUICKSTART.md` — user edits to install instructions

## Design decisions

- **Why multiplicative instead of replacement?** Replacement silently pointed at nonexistent paths when upstream steps had produced variant-suffixed directories. Multiplicative is the only semantic that preserves correct path propagation.
- **Why remove collapse?** Same path-breakage problem. Variant filtering (`--steps 400.random`) achieves the same goal without the broken-paths risk.
- **Why walk skipped steps?** Avoids hidden state files between runs. The TOML config fully determines the variant expansion, regardless of which steps are executed.
- **Why `[section_defaults]` instead of TOML inheritance?** TOML has no native inheritance mechanism. `[section_defaults]` + `[[section]]` merge is a simple, explicit pattern that avoids custom TOML extensions.
