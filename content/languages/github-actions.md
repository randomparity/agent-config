# GitHub Actions standards

On-demand reference for `shared/AGENTS.md` — read when a task touches workflows.

Pin actions to SHA hashes with version comments: `actions/checkout@<full-sha>  # vX.Y.Z` (use `persist-credentials: false`). Scan workflows with `zizmor` before committing. Configure Dependabot with 7-day cooldowns and grouped updates. Use `uv` ecosystem (not `pip`) for Python projects so Dependabot updates `uv.lock`.

## Required checks with path-filtered jobs

A path-filtered job set as a required status check deadlocks every PR that
doesn't touch its paths: the job skips, the check stays pending forever, and
the PR can never merge. Never require path-filtered jobs directly. Instead add
one aggregator job that depends on all of them, and make **only the
aggregator** required in branch protection:

```yaml
  ci-success:
    if: always()
    needs: [<every per-app job>]
    runs-on: ubuntu-latest
    steps:
      - name: Gate on all jobs
        env:
          RESULTS: ${{ join(needs.*.result, ' ') }}
        run: |
          for r in $RESULTS; do
            [ "$r" = "success" ] || [ "$r" = "skipped" ] || { echo "blocked by: $r"; exit 1; }
          done
```

`if: always()` makes the gate run even when upstream jobs fail or skip;
accepting `skipped` alongside `success` is what lets untouched-path PRs
through while still failing on any real failure or cancellation. Pass the
`needs.*.result` join through `env:` rather than interpolating `${{ }}`
directly into the `run:` script — that keeps the pattern clear of zizmor's
template-injection audit (see the `zizmor` note above). Add an escape hatch
so edits to the workflow file itself run every job (include the workflow
path in each job's path filter).
