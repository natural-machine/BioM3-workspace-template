# Extra Args Consolidation

**Date:** 2026-04-06 (fourth session)
**Pre-session state:** `git checkout 2f74a97`

## Summary

Consolidated named passthrough arguments into the `extra_args` mechanism across all pipeline steps. Previously, `run_pipeline.py` explicitly handled ~30 TOML keys that were simply reformatted as `--key value` and forwarded to shell scripts — duplicating the `extra_args` passthrough and requiring code changes whenever upstream added a CLI flag. Now `run_pipeline.py` only handles arguments it needs for its own logic (path derivation, validation, auto-detection, positional args), and everything else flows through `extra_args`.

## Changes

### `run_pipeline.py` — `_append_extra_args` separator parameter

Added a `separator` keyword argument (default `True`). When `True`, inserts `--` before extra args for shell scripts that parse their own flags and use `--` to delimit passthrough (Steps 200, 300). When `False`, appends args directly for shell scripts that either forward all args without parsing (Step 100) or parse all known flags themselves (Steps 400, 600, 610).

**Step 400 required `separator=False`** because its shell script runs two commands: `biom3_embedding_pipeline` (which accepts `--batch_size`) and `biom3_ProteoScribe_sample` (which doesn't). With `separator=True`, all extra_args bypassed the shell's flag routing and went to ProteoScribe, causing `unrecognized arguments: --batch_size`.

### `run_pipeline.py` — `get_step_variants` extra_args concatenation

Changed `extra_args` merge semantics for `[[section]]` variants with `[section_defaults]`. Previously, `{**defaults, **v}` caused variant `extra_args` to replace defaults `extra_args`. Now they are concatenated (defaults first, then variant), so `[generation_defaults]` extra_args and `[[generation]]` variant extra_args combine correctly. Argparse last-value-wins handles any overlapping flags.

### `run_pipeline.py` — `build_step_args` simplifications

| Step | Kept named | Removed | separator |
|------|-----------|---------|-----------|
| 100 | `training_csv` (path derivation), `pfam_ids` (validation) | 12 passthrough blocks (config, enrich_pfam, annotation_cache, etc.) | `False` |
| 200 | positional args only | pencl_weights, facilitator_weights, configs, batch_size, device | `True` |
| 300 | `epochs` (positional arg) | config, device | `True` |
| 400 | `model_weights` (auto-detection), `prompts_csv` (validation), hardcoded `--fasta` flags | 15 passthrough blocks (all model/inference/animation flags) | `False` |
| 600 | positional args only | db, threads, remote, local, max_targets conditional logic | `False` |
| 610 | positional args only | swissprot_dat, no_local_dat, alphafold_only, experimental_only | `False` |

### TOML config updates

All TOML configs updated to use `extra_args` with CLI-format flags (e.g., `"--enrich-pfam"` instead of `enrich_pfam = true`). Comments now reference the actual CLI entry points (`biom3_build_dataset`, `biom3_embedding_pipeline`, `biom3_pretrain_stage3`, `biom3_ProteoScribe_sample`) with `--help` pointers.

Variant documentation moved from per-step comments to the `[pipeline]` header, explaining single vs double bracket syntax, fan-out, cross-product, and `--steps 400.<variant>` filtering.

### New sample config

Added `_sample_pipeline_configs/full_demo.toml` — full pipeline (Steps 200-800) using the mini SH3 dataset (2 prompts), 3 finetuning epochs, pretrained SH3 weights.

## Files modified

- `run_pipeline.py` — `_append_extra_args`, `get_step_variants`, `build_step_args` (Steps 100-610)
- `configs/pipelines/_template.toml` — all step sections rewritten for extra_args pattern
- `configs/pipelines/test.toml` — updated to match
- `_sample_pipeline_configs/test.toml` — updated to match
- `_sample_pipeline_configs/full_demo.toml` — new
- `QUICKSTART.md` — updated embedding, finetuning, generation examples

## Design decisions

- **Why `separator=False` for Step 400?** The shell script runs two Python commands and routes flags to the correct one. `--` passthrough sent everything to ProteoScribe, breaking `--batch_size` which belongs to the embedding sub-command.
- **Why `separator=True` for Steps 200/300?** Their shell scripts don't know about every possible flag (e.g., Step 300 doesn't parse `--batch_size`). The `--` passthrough lets unknown flags reach the Python command directly.
- **Why concatenate extra_args in defaults/variant merge?** Simple dict merge (`{**defaults, **v}`) replaces lists entirely. Concatenation lets `[generation_defaults]` set shared flags and `[[generation]]` variants add their own, with argparse last-value-wins resolving overlaps.
- **Why `separator=False` for Steps 100/600/610?** Their shell scripts either forward all args directly (`$@` for Step 100) or parse all known flags (Steps 600/610). A `--` separator would cause argparse to misinterpret flags as positional args.
