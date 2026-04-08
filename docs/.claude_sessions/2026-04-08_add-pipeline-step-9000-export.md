# 2026-04-08: Add pipeline step 9000 (export)

## Summary

Added a new opt-in pipeline step 9000 that copies or symlinks selected
outputs from a finished run to user-specified destinations, driven by an
`export.config` TOML manifest. The step is non-destructive on the source,
idempotent on re-run, and follows the same "declared in `STEPS` but
excluded from `STEP_ORDER`" pattern as the existing 0900_webapp step — so
it only runs when explicitly added to `[pipeline].steps` or invoked via
`--steps 9000`.

The motivation: users finishing a pipeline run on a compute cluster
needed an automated way to ship a curated subset of `outputs/<FAMILY>/`
to a shared location (lab share, `BioM3-data-share/data/runs/`, another
machine's scratch dir) with a record of what was published. Step 9000
closes that gap as the optional last step of any pipeline run.

## Pre-session state

```bash
git checkout e9e15c7
```

Plus a populated `outputs/SH3_mini_demo/` directory used as the smoke-test
fixture.

## Files added

- [scripts/export_outputs.py](../../scripts/export_outputs.py) — Python
  CLI that does all the actual export work (TOML parsing, idempotency
  hashing, copy/symlink ops).
- [pipeline/9000_export.sh](../../pipeline/9000_export.sh) — thin shell
  wrapper that mirrors the [pipeline/0800_plot_results.sh](../../pipeline/0800_plot_results.sh)
  pattern: validate args, header echo, invoke
  `python scripts/export_outputs.py "$@"`, footer echo.

## Files modified

- [run_pipeline.py](../../run_pipeline.py) — added `"9000"` entries to
  `STEPS`, `STEP_NAMES`, `STEP_SECTIONS`, and `STEP_SUBDIRS`; added
  `case "9000":` branches in `build_step_args` and `get_step_outputs`;
  stashed `d["config_dir"]` in `main()` so the export config path can be
  resolved relative to the pipeline TOML's directory.
- [configs/pipelines/_template.toml](../../configs/pipelines/_template.toml) —
  added `[export]` section example block, listed `9000` in the
  `Available steps:` comment, extended the `[environments].biom3` comment
  to include 9000.
- [CLAUDE.md](../../CLAUDE.md) — updated repo-layout pipeline-script range
  to `9000_export.sh`, added a sentence to "Building and running"
  describing step 9000.
- [QUICKSTART.md](../../QUICKSTART.md) — added a `9000 | Export | ...`
  row to the pipeline overview table, extended the intro paragraph to
  mention the two optional post-pipeline steps, added an `[export]`
  example block alongside `[webapp]`.

## Design decisions

1. **All work lives in `scripts/export_outputs.py`; the shell script is a
   thin wrapper.** This matches the strict convention of every existing
   pipeline step: shell scripts validate args and echo headers, then
   invoke a Python entry-point (`biom3_build_dataset`, `biom3_app`,
   `python scripts/make_plots.py`, etc.). Doing TOML parsing, hashing,
   and copy/symlink ops in Python (`tomllib`, `hashlib`, `shutil`,
   `pathlib`) is dramatically cleaner than shell-side, and `scripts/`
   already houses the analogous helpers (`make_plots.py`,
   `fetch_hit_structures.py`, `samples_to_fasta.py`,
   `create_mini_dataset.py`). The closest precedent is
   [pipeline/0800_plot_results.sh:81](../../pipeline/0800_plot_results.sh#L81),
   which calls `python scripts/make_plots.py "${plot_args[@]}"`.

2. **Step 9000 is excluded from `STEP_ORDER`.** It runs via the existing
   `extras` loop at [run_pipeline.py:740-747](../../run_pipeline.py#L740-L747),
   which already handles "any requested step not in `STEP_ORDER` runs
   after the walk completes". No special-casing needed in `main()` —
   same pattern as `0900_webapp`.

3. **Default mode is `symlink`.** Matches the spec and the precedent of
   `scripts/sync_weights.sh`. Symlinks are dramatically faster on large
   `outputs/` trees and don't double the storage footprint.

4. **Idempotency via md5 compare for copies, `Path.resolve()` compare
   for symlinks.** Files hashed with `hashlib.md5` streaming. Directories
   hashed by walking `Path.rglob('*')`, hashing each regular file, and
   combining (sorted, with relative-path prefixes to defeat reordering).
   Symlinks: `dst.resolve() == src.resolve()`. Re-running with no
   changes reports `OK (already in sync)` for every entry and exits 0.

5. **Replace-on-mismatch is in-place.** If `dst` exists but does not
   match the source (different md5 for copies; different target for
   symlinks), the script `shutil.rmtree`s or `unlink`s and re-creates
   it. Safe because the destination is owned by the user and the source
   under `outputs/<FAMILY>/` is never touched.

6. **`export.config` path is resolved relative to the pipeline TOML's
   directory.** This matches how a user thinks about "this run's export
   manifest" — they keep the manifest next to the pipeline config. To
   make the pipeline-config directory available inside `build_step_args`,
   `main()` stashes `d["config_dir"] = str(args.config.resolve().parent)`
   immediately after `derive_paths()`. The new `case "9000"` branch then
   resolves `cfg["export"]["config"]` against that directory.

7. **`get_step_outputs("9000", d)` re-parses the export.config at
   display time.** During `--dry-run`, the runner builds an output tree
   from `get_step_outputs`. For step 9000 it re-reads the export.config
   with `tomllib` (~6 lines duplicated; not worth importing across
   `run_pipeline.py` ↔ `scripts/`) and returns the absolute `dst`
   paths. Falls back to `[]` if the file is unreadable so dry-run never
   crashes. The `build_step_args` case mutates `d` to leave
   `export_config_path` behind for `get_step_outputs` — small wart but
   matches how `derive_variant_paths` already mutates `d`.

8. **Fail-fast on first missing source (default).** The spec says
   "default behavior is to exit non-zero **on the first missing
   source**". The Python CLI checks each `export_one()` result and
   `return 1`s immediately if a `failed` is seen, with an explicit
   `aborting on first failure (use --skip-missing to continue)` log
   line. Under `--skip-missing`, missing sources become `skipped` and
   the loop continues.

9. **All progress lines go to stdout, not stderr.** Initially I had
   `WARN missing src:` and `aborting on first failure` going to stderr,
   but that produced jumbled output when run through anything that
   captures only stdout. Unified on stdout — the script's exit code
   conveys success/failure, which is consistent with how the other
   pipeline steps handle status.

## Verification

All scenarios run against `outputs/SH3_mini_demo/`. A throwaway
`/tmp/test_export.config` with two entries (one `copy`, one `symlink`)
plus a missing-source variant.

| Scenario | Expected | Actual |
|---|---|---|
| Standalone dry-run | Two `WOULD ...` lines, no FS changes, exit 0 | ✓ |
| Standalone real run | Files/symlinks created, exit 0 | ✓ |
| Copy md5 matches source | Identical md5 between src and dst | ✓ |
| Symlink resolves correctly | `readlink` points at the absolute src path | ✓ |
| Idempotent re-run | Both report `OK (already in sync)`, exit 0 | ✓ |
| Replace-on-mismatch | Modified dst gets overwritten back to source md5 | ✓ |
| Missing src, no `--skip-missing` | `WARN missing src` + `aborting` + exit 1 | ✓ |
| Missing src, `--skip-missing` | `WARN` line, other entries continue, exit 0 | ✓ |
| Pipeline runner dry-run | Step header + Args list + dry-run output tree containing dst paths | ✓ |
| Pipeline runner real run | End-to-end conda activation + script execution + exit 0 | ✓ |
| Pipeline runner idempotent re-run | All `OK (already in sync)`, exit 0 | ✓ |
| `extra_args = ["--skip-missing"]` passthrough | `--skip-missing` reaches the Python CLI | ✓ |

## Lingering issues / not addressed

- **Cosmetic: dry-run output tree roots dst paths under `output_dir/`**
  even when the dst paths are absolute and outside `output_dir`. This is
  because `_build_tree` lstrips `/` from any path that doesn't share the
  `output_dir` prefix, then renders it as if it were a relative subpath.
  For step 9000 this means `/tmp/biom3_export_test/...` shows up under
  `outputs/SH3_mini_demo/` in the tree header. Not a functional bug, but
  the tree presentation could be improved by giving step 9000 its own
  output section in `print_output_tree`. Deferred.

- **`outputs/<FAMILY>/` referenced by absolute path in dst** is not
  validated. A user could write `dst = "../../etc/passwd"` and the
  script would happily symlink to it. This is by design — the dst path
  is user-controlled and the user is expected to know what they're
  doing. Worth a mention in user-facing docs if step 9000 sees
  significant adoption.

- **Variant fan-out**: when a pipeline run has multiple variant contexts
  (e.g. generation variants), step 9000 in the `extras` loop runs once
  per active context. Since the script is idempotent this is harmless
  (subsequent runs report `already in sync`), but it produces noisy
  output. Acceptable for v1; if it becomes a problem we can dedupe in
  the runner.

- **No tests under `tests/`** for `scripts/export_outputs.py`. The
  workspace template repo has no test infrastructure today, so adding
  one just for this script would be out of scope. The verification
  matrix above served as a manual smoke test.

## Commit

```
feat: add pipeline step 9000 export
```
