# 2026-04-08: Switch step 9000 export config from TOML to configs/export.json

## Summary

Refactored the freshly-landed step 9000 (export) so its config file is
JSON at a fixed default location (`configs/export.json`) instead of a
TOML file (`export.config`) resolved relative to the pipeline TOML's
directory. This makes step 9000 consistent with how every other config
path in the workspace is handled — a real file under `configs/`, not a
loose sibling of the pipeline TOML.

The refactor came one commit after the original step 9000 implementation
in [ab79cf9](../../) — same day, same direction, but cleaner now that
the format follows the existing convention rather than inventing a new
parallel one.

## Pre-session state

```bash
git checkout ab79cf9
```

## Files modified

- [scripts/export_outputs.py](../../scripts/export_outputs.py) — replaced
  `tomllib` with `json`; switched the schema from TOML `[[entry]]` blocks
  to a JSON object with an `"entries"` array of `{src, dst, mode}`. Added
  explicit `isinstance(cfg, dict)` and `isinstance(e, dict)` validation
  for the JSON shape, plus a clean error message wrapping
  `json.JSONDecodeError`. The optional `_comment` top-level key is
  silently ignored by the parser.
- [pipeline/9000_export.sh](../../pipeline/9000_export.sh) — header
  docstring + variable rename (`export_config` → `export_json`) + example
  line now uses `configs/export.json`.
- [run_pipeline.py](../../run_pipeline.py) — added `import json`;
  switched `get_step_outputs("9000", ...)` to `json.load` and to read
  the new `"entries"` key (with `isinstance` guards); changed the
  `build_step_args` default from `"export.config"` to
  `"configs/export.json"` and switched the resolution semantic so
  relative paths resolve against `SCRIPT_DIR` (the workspace root via
  `Path(__file__).resolve().parent`) instead of against the pipeline
  TOML's parent directory. Removed the now-unused
  `d["config_dir"] = str(args.config.resolve().parent)` stash from
  `main()`.
- [configs/pipelines/_template.toml](../../configs/pipelines/_template.toml) —
  `[export]` example block updated to point at `configs/export.json` and
  to describe the new resolution rule (workspace-root-relative or
  absolute, never pipeline-config-relative).
- [CLAUDE.md](../../CLAUDE.md) — replaced "via an `export.config` TOML
  file" with a markdown link to `configs/export.json`.
- [QUICKSTART.md](../../QUICKSTART.md) — updated the `[export]` example
  block and the row in the pipeline-overview table.

## Files added

- [configs/export.json](../../configs/export.json) — new template file
  with two example entries (one `copy`, one `symlink`) using
  `/REPLACE_ME/path/to/destination/...` placeholder dst paths and a
  top-level `_comment` field describing the schema. Users copy this as
  the starting point and edit the dst paths to point at their lab share
  or other destination.

## Design decisions

1. **Default location is `configs/export.json`, not next to the
   pipeline TOML.** This matches every other config path in the repo:
   `configs/dbio_config.json`, `configs/inference/*.json`,
   `configs/stage3_training/*.json` are all real files under `configs/`.
   The original "relative to the pipeline TOML's directory" semantic was
   unique to step 9000 and inconsistent with everything else.

2. **Path resolution against `SCRIPT_DIR`, not cwd.** Relative paths in
   `[export].config` resolve against
   `Path(__file__).resolve().parent` (the workspace root, since
   `run_pipeline.py` lives at the repo root), so behavior is independent
   of the user's actual cwd when invoking the runner. Absolute paths
   pass through unchanged. This removed the need for the `d["config_dir"]`
   stash that was added in the original step 9000 commit just to support
   pipeline-config-relative resolution.

3. **JSON schema uses `"entries"` (plural).** The TOML version was
   `[[entry]]` (singular), but plural is the idiomatic JSON convention
   and matches how downstream code reads it (`for e in entries: ...`).
   Since this is a fresh format change rather than a migration of
   existing user files, no backward compatibility was needed.

4. **`_comment` top-level field is parser-ignored.** JSON has no comment
   syntax. The convention in many JSON config schemas is to allow a
   `_comment` key that the parser silently drops (it's not enumerated in
   the validation, just ignored because the parser only reads `entries`).
   The template `configs/export.json` uses this to embed the schema
   description right next to the data.

5. **Placeholder dst paths use `/REPLACE_ME/`.** A clearly fake prefix
   that fails loudly if a user runs step 9000 without editing the file.
   An empty `entries: []` was considered but rejected — the example
   entries do double duty as inline documentation.

6. **`[export]` section in the pipeline TOML is now optional.** Step
   9000 already worked without an `[export]` section in the original
   commit (because `vc.get(...)` falls back to a default), but now the
   default actually points at a real file that ships with the template
   (`configs/export.json`). A user can run `--steps 9000` against an
   unmodified pipeline TOML and the runner will pick up
   `configs/export.json` automatically.

## Verification

All scenarios run against `outputs/SH3_mini_demo/`. Throwaway test JSON
+ pipeline TOML files in `/tmp/`.

| Scenario | Result |
|---|---|
| Standalone dry-run with JSON config | ✓ |
| Standalone real run (copy + symlink) | ✓ |
| Standalone idempotent re-run | ✓ |
| Runner `--dry-run` with absolute config override | ✓ Args show absolute path; output tree lists dst paths |
| Runner `--dry-run` with NO `[export]` section | ✓ Defaults to `<repo>/configs/export.json` regardless of cwd; tree shows the template's REPLACE_ME paths; `_comment` field silently ignored |
| Malformed JSON | ✓ `ERROR: invalid JSON in <path>: Expecting property name enclosed in double quotes: line 1 column 3 (char 2)`, exit 1 |

## Lingering issues / not addressed

- The session note from the previous commit
  ([2026-04-08_add-pipeline-step-9000-export.md](2026-04-08_add-pipeline-step-9000-export.md))
  still describes the original TOML format and the
  pipeline-config-relative resolution rule. It's an accurate snapshot of
  *that* commit's design, so I left it alone — this new note documents
  the change. If the divergence becomes confusing, the older note could
  get a one-line "superseded by ..." pointer.

- The `configs/export.json` template ships with `/REPLACE_ME/...`
  placeholder dst paths. If a user adds `9000` to `[pipeline].steps`
  without editing the file, `mkdir -p` will happily create
  `/REPLACE_ME/path/to/destination/` as a real subdirectory of `/`
  (assuming permissions). Considered rejecting paths starting with
  `/REPLACE_ME` in the parser, but decided against — it's user paranoia
  for an opt-in step where the user explicitly added 9000 to their
  pipeline. The clear placeholder name surfaces the issue at code-review
  time.

- The cosmetic "dry-run output tree roots dst paths under
  `output_dir/`" issue noted in the previous session is still present
  (and now even more visible because the placeholder paths under
  `/REPLACE_ME/...` show up nested under `outputs/SH3_mini_demo/` in the
  tree). Same deferral — fixing it would mean restructuring
  `print_output_tree` to support multiple root sections, which is out of
  scope for this format refactor.

- No test for the case where the config file references absolute dst
  paths that overlap with the workspace's own `outputs/<FAMILY>/`
  directory (a user could accidentally create a self-referential
  symlink loop). Not a real-world risk for the export step since users
  ship outputs OUT of the workspace, but worth keeping in mind if step
  9000 grows additional path-validation features.

## Commit

`c90a0dc` — refactor: switch step 9000 export config from TOML to configs/export.json
