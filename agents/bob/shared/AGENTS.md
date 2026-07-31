# Global Development Standards

These instructions are public defaults for IBM Bob users who install this
repository. Project-local `AGENTS.md` files and `.bob/rules/` files may add
project context.

- Keep host-specific paths, trusted-project lists, local IP addresses, auth
  headers, API keys, runtime state, and caches out of committed files.
- Use installed skills when they match the work. For multi-step changes, write
  a plan first and execute it task by task. Before reporting completion, run
  the relevant verification commands and check the output.
- Prefer explicit, readable code over clever shortcuts. Add dependencies only
  when they remove more maintenance burden than they add.
- Test behavior and handled error paths. Mock external boundaries, not the
  logic under test.
- When editing this repository, run `./install-test.sh` and
  `./scripts/check-public-safety.sh` before reporting completion.
