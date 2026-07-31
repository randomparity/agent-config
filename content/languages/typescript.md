# Node/TypeScript standards

On-demand reference for `shared/AGENTS.md` — read when a task touches Node or TypeScript.

**Runtime:** Node 22 LTS, ESM only (`"type": "module"`)

| purpose | tool |
|---------|------|
| lint | `oxlint` |
| format | `oxfmt` |
| test | `vitest` |
| types | `tsc --noEmit` |

**Always use oxlint and oxfmt** over eslint/prettier — they're faster and stricter. Enable `typescript`, `import`, `unicorn` plugins.

**tsconfig.json strictness** — enable all of these:
```jsonc
"strict": true,
"noUncheckedIndexedAccess": true,
"exactOptionalPropertyTypes": true,
"noImplicitOverride": true,
"noPropertyAccessFromIndexSignature": true,
"verbatimModuleSyntax": true,
"isolatedModules": true
```

Colocated `*.test.ts` files. Supply chain: `pnpm audit --audit-level=moderate` before installing, pin exact versions (no `^` or `~`), enforce 24-hour publish delay (`pnpm config set minimumReleaseAge 1440`), block postinstall scripts (`pnpm config set ignore-scripts true`).
