# Global Development Standards

Keep committed configuration public-safe. Host-specific values, local project
inventories, private MCP credentials, local network addresses, and absolute user
paths belong in private overlays outside this repository.

For multi-step work, write down the plan, implement in small verified steps, and
run the relevant guardrails before reporting completion. For this repository,
the guardrails are:

Host architecture and project target architectures are separate facts.
Applicable project-local instructions and policy are authoritative for target architectures.
Before
architecture-sensitive generation, build, or verification, run `preflight` and retain
its recorded host, effective targets, and relationship. Never infer a target from the
host or drop a declared target because it differs from the current machine.

```sh
shellcheck install.sh install-tools.sh install-test.sh scripts/*.sh
shfmt -d install.sh install-tools.sh install-test.sh scripts/*.sh
./install-test.sh
./scripts/check-public-safety.sh
```
