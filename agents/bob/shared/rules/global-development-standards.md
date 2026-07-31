# Global Development Standards

Keep committed configuration public-safe. Host-specific values, local project
inventories, private MCP credentials, local network addresses, and absolute user
paths belong in private overlays outside this repository.

For multi-step work, write down the plan, implement in small verified steps, and
run the relevant guardrails before reporting completion. For this repository,
the guardrails are:

```sh
shellcheck install.sh install-tools.sh install-test.sh scripts/*.sh
shfmt -d install.sh install-tools.sh install-test.sh scripts/*.sh
./install-test.sh
./scripts/check-public-safety.sh
```
