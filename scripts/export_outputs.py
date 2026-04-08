#!/usr/bin/env python
"""Export selected pipeline outputs to user-specified destinations.

Driven by a JSON config (default: configs/export.json) with an "entries"
array. Each entry copies or symlinks a path from <outputs_dir> to a
destination path. Idempotent (re-running with no changes reports
"already in sync") and non-destructive on the source.

Schema:
    {
      "entries": [
        {"src": "samples/all_sequences.fasta", "dst": "/abs/path", "mode": "copy"},
        {"src": "images", "dst": "/abs/path", "mode": "symlink"}
      ]
    }

Usage:
    python scripts/export_outputs.py <export_json> <outputs_dir>
    python scripts/export_outputs.py <export_json> <outputs_dir> --dry-run
    python scripts/export_outputs.py <export_json> <outputs_dir> --skip-missing
"""

import argparse
import hashlib
import json
import shutil
import sys
from pathlib import Path

PROGRESS = "[step 9000 export]"
VALID_MODES = ("copy", "symlink")


def md5_file(path: Path) -> str:
    h = hashlib.md5()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def md5_dir(path: Path) -> str:
    """Hash a directory by combining md5s of all regular files in sorted order."""
    combined = hashlib.md5()
    for entry in sorted(path.rglob("*")):
        if not entry.is_file() or entry.is_symlink():
            continue
        rel = entry.relative_to(path).as_posix()
        combined.update(rel.encode())
        combined.update(b"\0")
        combined.update(md5_file(entry).encode())
        combined.update(b"\n")
    return combined.hexdigest()


def compute_hash(path: Path) -> str:
    if path.is_file() and not path.is_symlink():
        return md5_file(path)
    if path.is_dir():
        return md5_dir(path)
    return ""


def load_entries(config_path: Path) -> list[dict]:
    with open(config_path) as f:
        try:
            cfg = json.load(f)
        except json.JSONDecodeError as exc:
            sys.exit(f"{PROGRESS} ERROR: invalid JSON in {config_path}: {exc}")
    if not isinstance(cfg, dict):
        sys.exit(
            f"{PROGRESS} ERROR: top-level JSON must be an object in {config_path}"
        )
    entries = cfg.get("entries", [])
    if not isinstance(entries, list):
        sys.exit(
            f'{PROGRESS} ERROR: "entries" must be an array in {config_path}'
        )
    for e in entries:
        if not isinstance(e, dict):
            sys.exit(f"{PROGRESS} ERROR: entry must be an object: {e}")
        if "src" not in e or "dst" not in e:
            sys.exit(f"{PROGRESS} ERROR: entry missing src or dst: {e}")
        e.setdefault("mode", "symlink")
        if e["mode"] not in VALID_MODES:
            sys.exit(
                f"{PROGRESS} ERROR: invalid mode {e['mode']!r} for "
                f"src={e['src']} (must be one of {VALID_MODES})"
            )
    return entries


def already_in_sync(src_abs: Path, dst: Path, mode: str) -> bool:
    if mode == "symlink":
        if not dst.is_symlink():
            return False
        try:
            return dst.resolve() == src_abs.resolve()
        except OSError:
            return False
    if not dst.exists():
        return False
    if dst.is_symlink():
        return False
    return compute_hash(src_abs) == compute_hash(dst)


def remove_existing(dst: Path) -> None:
    if dst.is_symlink() or (dst.exists() and not dst.is_dir()):
        dst.unlink()
    elif dst.is_dir():
        shutil.rmtree(dst)


def export_one(
    entry: dict,
    outputs_dir: Path,
    *,
    dry_run: bool,
    skip_missing: bool,
) -> str:
    """Process a single entry. Returns one of:
    'exported', 'in_sync', 'skipped', 'failed'.
    """
    src_rel = entry["src"]
    dst = Path(entry["dst"])
    mode = entry["mode"]
    src_abs = outputs_dir / src_rel

    if not src_abs.exists() and not src_abs.is_symlink():
        print(f"{PROGRESS} WARN missing src: {src_abs}")
        return "skipped" if skip_missing else "failed"

    if already_in_sync(src_abs, dst, mode):
        print(f"{PROGRESS} OK (already in sync) {mode} {src_rel} -> {dst}")
        return "in_sync"

    verb = "WOULD" if dry_run else "OK"
    print(f"{PROGRESS} {verb} {mode} {src_rel} -> {dst}")

    if dry_run:
        return "exported"

    dst.parent.mkdir(parents=True, exist_ok=True)
    if dst.is_symlink() or dst.exists():
        remove_existing(dst)

    if mode == "symlink":
        dst.symlink_to(src_abs.resolve())
    else:
        if src_abs.is_dir():
            shutil.copytree(src_abs, dst)
        else:
            shutil.copy2(src_abs, dst)

    return "exported"


def parse_args(argv):
    parser = argparse.ArgumentParser(
        description="Export selected pipeline outputs to user-specified destinations",
    )
    parser.add_argument(
        "export_config", type=Path,
        help='Path to export JSON file with an "entries" array',
    )
    parser.add_argument(
        "outputs_dir", type=Path,
        help="Per-family outputs root (src paths are relative to this)",
    )
    parser.add_argument(
        "--dry-run", action="store_true",
        help="Print actions that would be taken without touching the filesystem",
    )
    parser.add_argument(
        "--skip-missing", action="store_true",
        help="Warn and continue when a src does not exist (default: exit non-zero)",
    )
    return parser.parse_args(argv)


def main(argv=None):
    args = parse_args(argv)

    if not args.export_config.is_file():
        sys.exit(f"{PROGRESS} ERROR: export config not found: {args.export_config}")
    if not args.outputs_dir.is_dir():
        sys.exit(f"{PROGRESS} ERROR: outputs directory not found: {args.outputs_dir}")

    entries = load_entries(args.export_config)
    if not entries:
        print(f"{PROGRESS} no entries in {args.export_config} — nothing to do")
        return 0

    counts = {"exported": 0, "in_sync": 0, "skipped": 0, "failed": 0}
    for entry in entries:
        result = export_one(
            entry, args.outputs_dir,
            dry_run=args.dry_run, skip_missing=args.skip_missing,
        )
        counts[result] += 1
        if result == "failed":
            # Fail-fast on first missing source (unless --skip-missing).
            print(
                f"{PROGRESS} aborting on first failure "
                f"(use --skip-missing to continue)"
            )
            return 1

    print()
    print("=== Export Summary ===")
    print(f"  Exported:   {counts['exported']}")
    print(f"  In sync:    {counts['in_sync']}")
    print(f"  Skipped:    {counts['skipped']}")
    print(f"  Failed:     {counts['failed']}")

    return 0


if __name__ == "__main__":
    sys.exit(main())
