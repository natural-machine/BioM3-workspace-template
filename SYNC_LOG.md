# BioM3-dev Sync Log

Tracks synchronization points between this repository and
the core [BioM3-dev](https://github.com/addison-nm/BioM3-dev) library.

The pinned BioM3-dev version is also surfaced in [requirements/biom3.txt](requirements/biom3.txt) so it can be installed via `pip install -r requirements/biom3.txt`. Bump that file in lockstep with adding a new row here.

| Date | BioM3-dev commit | BioM3-dev version | workspace commit | Summary |
| ---- | ---------------- | ----------------- | ---------------- | ------- |
| 2026-04-10 | `eb05390` | `v0.1.0a3` | `a3275df` | Sync against BioM3-dev HEAD: bump to v0.1.0a3, add versioning guide and incident narrative correction, merge addison-spark; workspace-template adds pipeline step 9000 export and refactors its config TOML → JSON |
| 2026-04-08 | `8c8e23c` | `v0.1.0a1` | `e9e15c7` | First recorded sync point. workspace-template HEAD adds `[comparison]` and `[plotting]` section headers for steps 700/800; tested against BioM3-dev HEAD with PAD probability gauge in animations |

## How to use this log

After syncing with BioM3-dev changes:
1. Add a new row at the top of the table
2. Record the BioM3-dev commit hash you synced up to
3. Record the BioM3-dev version at that commit (read from `biom3.__version__` or check `src/biom3/__init__.py` in BioM3-dev)
4. Bump [requirements/biom3.txt](requirements/biom3.txt) to match the new BioM3-dev pin
5. Record the resulting workspace commit hash (fill in after committing)
6. Write a brief summary of what changed

## Checking for upstream changes

```bash
cd /path/to/BioM3-dev
git log --oneline <last-synced-commit>..HEAD
```
