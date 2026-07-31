# Agent Config Repository Instructions

This is a public repository for shared Claude Code, Codex, and IBM Bob
configuration. Do not commit host-specific overlays, trusted project lists,
absolute user paths, local hostnames, local IP addresses, auth headers, API
keys, runtime state, caches, or tool-generated session data.

Private overlays belong outside this repo under:

```text
${AGENT_CONFIG_PRIVATE_DIR:-$HOME/.config/agent-config}/hosts/<host>/<agent>/
```

Keep shared prose in `content/` only when it is agent-neutral. Keep native
settings, instruction files, commands, skills, modes, and MCP files under
`agents/<agent>/shared/`.

Run `just setup` before local development to install repo tooling and enable
git hooks.

Run these guardrails before reporting completion:

```sh
just verify
```
