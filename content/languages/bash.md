# Bash standards

On-demand reference for `shared/AGENTS.md` — read when a task touches shell scripts.

All scripts must start with `set -euo pipefail`. Lint: `shellcheck script.sh && shfmt -d script.sh`
