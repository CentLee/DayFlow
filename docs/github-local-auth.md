# DayFlow Local GitHub Auth

DayFlow keeps GitHub CLI authentication inside the ignored runner directory so it does not overwrite the operator's global configuration.

## Local Store

The default path is `.dayflow/gh` in the repository root.

```bash
mkdir -p .dayflow/gh
GH_CONFIG_DIR="$PWD/.dayflow/gh" gh auth login -h github.com
GH_CONFIG_DIR="$PWD/.dayflow/gh" gh auth status -h github.com
```

For token login:

```bash
printf '%s' '<GITHUB_PAT>' | GH_CONFIG_DIR="$PWD/.dayflow/gh" gh auth login -h github.com --with-token
```

The runner automatically uses this directory. `GH_CONFIG_DIR` may override it for one invocation.

On first non-dry run, an existing `.symphony/gh` directory is copied to `.dayflow/gh` when the destination does not exist. The legacy source is never deleted because it also protects paused CEN-28 work.

Do not run global GitHub auth setup as part of runner execution, and never commit either auth directory.
