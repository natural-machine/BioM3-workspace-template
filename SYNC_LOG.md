# BioM3-dev Sync Log

Tracks synchronization points between this repository and
the core [BioM3-dev](https://github.com/addison-nm/BioM3-dev) library.

| Date | BioM3-dev commit | workspace commit | Summary |
| ---- | ---------------- | ---------------- | ------- |

## How to use this log

After syncing with BioM3-dev changes:
1. Add a new row at the top of the table
2. Record the BioM3-dev commit hash you synced up to
3. Record the resulting workspace commit hash (fill in after committing)
4. Write a brief summary of what changed

## Checking for upstream changes

```bash
cd /path/to/BioM3-dev
git log --oneline <last-synced-commit>..HEAD
```
