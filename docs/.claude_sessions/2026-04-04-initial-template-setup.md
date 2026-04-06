# 2026-04-04: Initial template repository setup

## Summary

Created the initial file structure for BioM3-workspace-template, the GitHub template repository for new BioM3 research workspaces (repo 4 of 4 in the ecosystem).

## What was created

| File | Description |
|------|-------------|
| `README.md` | Template usage guide: ecosystem table, quick start, directory structure, shared data paths |
| `CLAUDE.md` | AI assistant context matching sibling repo format |
| `docs/biom3_ecosystem.md` | Exact copy from BioM3-dev (canonical cross-repo reference) |
| `.gitignore` | Based on BioM3-workflow-demo; ignores data/, weights/, outputs/, logs/, .claude/ |

Skeleton directories with `.gitkeep`: `configs/`, `pipeline/`, `scripts/`, `docs/.claude_sessions/`

## Design decisions

- Mirrors BioM3-workflow-demo directory structure but contains no demo-specific data, configs, or outputs
- README quick start walks through: clone → install BioM3-dev → source environment.sh → symlink weights → add data → configure pipeline → run
- Shared data paths table covers all three machines (DGX Spark, Polaris, Aurora)
- `docs/biom3_ecosystem.md` copied verbatim from BioM3-dev per the cross-repo convention (HTML comment at top notes this)
- Gitignored directories (data/, weights/, outputs/, logs/) are not pre-created — researcher creates them during setup

## Notes

- Session was run from BioM3-data-share working directory but files were written to the BioM3-workspace-template repo
- The `biom3_ecosystem.md` still says "*(Planned)*" for workspace-template — this should be updated across all repos once the template is published
