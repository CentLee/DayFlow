# DayFlow Local GitHub Auth

Use repo-local GitHub CLI auth for DayFlow automation.

## Why

- this machine already uses global `gh` config for other work
- DayFlow should not overwrite `~/.config/gh`
- Symphony and Codex should use a repo-scoped auth store only

## Local Config Directory

DayFlow uses:

- `/Users/kakao_ent/Documents/DayFlow/.symphony/gh`

Symphony is configured to launch Codex with:

- `GH_CONFIG_DIR=/Users/kakao_ent/Documents/DayFlow/.symphony/gh`

That keeps GitHub CLI auth scoped to this repository's automation setup.

## Login Command

Run this from the DayFlow repo when you want to refresh GitHub auth for Symphony:

```bash
mkdir -p /Users/kakao_ent/Documents/DayFlow/.symphony/gh
GH_CONFIG_DIR=/Users/kakao_ent/Documents/DayFlow/.symphony/gh gh auth login -h github.com
```

Or with a token:

```bash
mkdir -p /Users/kakao_ent/Documents/DayFlow/.symphony/gh
printf '%s' '<GITHUB_PAT>' | GH_CONFIG_DIR=/Users/kakao_ent/Documents/DayFlow/.symphony/gh gh auth login -h github.com --with-token
```

## Verification

```bash
GH_CONFIG_DIR=/Users/kakao_ent/Documents/DayFlow/.symphony/gh gh auth status -h github.com
```

## Notes

- do not run `gh auth setup-git` globally for this repo-only workflow
- if push or PR creation is needed, ensure the local auth directory is valid first
