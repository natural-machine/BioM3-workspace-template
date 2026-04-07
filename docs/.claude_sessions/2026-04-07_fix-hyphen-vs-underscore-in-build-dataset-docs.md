# 2026-04-07: Fix hyphen vs underscore in build_dataset script docs

## Summary

Audited all pipeline script bash headers for correctness in how they call
biom3 CLI entrypoints, specifically looking for `-` vs `_` mismatches.
Found and fixed the header/usage documentation in `0100_build_dataset.sh`,
which still used hyphenated flag names after commit `0ed7ffe` switched
`biom3_build_dataset` to underscored flags.

## Pre-session state

```bash
git checkout 0ed7ffe
```

## Details

### Problem

Commit `0ed7ffe` (in BioM3-dev) changed `biom3_build_dataset` CLI flags
from hyphens to underscores (e.g. `--pfam-ids` -> `--pfam_ids`). The
pipeline script `0100_build_dataset.sh` passes user args through via
`"$@"`, so its header comments and usage echo block were the only
reference users had for flag names -- and they still showed the old
hyphenated form. A user copying flags from the docs would get argparse
errors.

### Flags updated (all in `pipeline/0100_build_dataset.sh`)

| Before (wrong)       | After (correct)       |
|----------------------|-----------------------|
| `--pfam-ids`         | `--pfam_ids`          |
| `--output-filename`  | `--output_filename`   |
| `--databases-root`   | `--databases_root`    |
| `--enrich-pfam`      | `--enrich_pfam`       |
| `--annotation-cache` | `--annotation_cache`  |
| `--uniprot-dat`      | `--uniprot_dat`       |
| `--add-taxonomy`     | `--add_taxonomy`      |
| `--taxonomy-filter`  | `--taxonomy_filter`   |
| `--taxid-index`      | `--taxid_index`       |
| `--chunk-size`       | `--chunk_size`        |

Affected locations: header comment block (lines 14-54) and usage echo
block (lines 77-88).

### What was verified correct (no changes needed)

- `run_pipeline.py` already uses underscores when building Step 100 args.
- `_template.toml` `[build_dataset]` extra_args already use underscores.
- Scripts 0200-0400 correctly use underscores for biom3 CLI flags.
- Scripts 0600, 0610, 0800 use hyphens for their own shell-level flags
  (not biom3 CLI flags) -- this is correct and consistent.
- `biom3_embedding_pipeline`, `biom3_pretrain_stage3`,
  `biom3_ProteoScribe_sample`, and `biom3_app` flags all matched their
  respective script invocations.
