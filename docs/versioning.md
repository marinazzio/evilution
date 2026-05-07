# Versioning & Upgrade Policy

This document defines what `evilution` promises across releases.

## SemVer interpretation (1.x)

| Bump          | Triggered by                                                                 |
|---------------|-------------------------------------------------------------------------------|
| MAJOR (`2.0`) | Removing or renaming anything in the public contract; changing semantics; tightening input validation. |
| MINOR (`1.X`) | Adding a new CLI flag, config key, mutation operator, public Ruby method, or session/MCP field; relaxing validation; adding an operator to the `default` profile (whether brand-new or promoted from `strict`). |
| PATCH (`1.X.Y`) | Bug fix, performance improvement, documentation, internal refactor with no observable contract effect. |

## Public contract surface

The following surfaces are covered by the SemVer guarantees above. Each one is defined in detail in its own document; this list is the canonical inventory.

- **Public Ruby API** — see [`docs/public_api.md`](public_api.md). Classes and methods not listed there are internal and may change in any release.
- **CLI flags and commands** — the README "Command Reference" tables are the authoritative list.
- **`.evilution.yml` configuration keys** — see [`docs/config.md`](config.md). The file carries an explicit `schema_version`.
- **Session JSON files** (`.evilution/results/*.json`) — see [`docs/session_schema.md`](session_schema.md). Files include a `schema_version` field; consumers (`compare`, session diff, HTML reporter) handle older versions explicitly or fail loudly.
- **MCP tool input/output schemas** (`evilution-mutate`, `evilution-session`, `evilution-info`) — see [`docs/mcp.md`](mcp.md).
- **Process exit codes** — `0` pass, `1` fail, `2` error. Documented in the README "Exit Codes" section.

Anything not on this list is internal. It can change in any release without a deprecation cycle.

## Deprecation cycle

When a feature on the public contract surface is deprecated:

1. It is marked with the YARD `@deprecated` tag (Ruby API), or with a deprecation note in the relevant doc table (CLI flags, config keys, MCP fields).
2. Where the call site is reachable at runtime, a one-line warning is emitted (`warn` to stderr, gated by an `EVILUTION_HIDE_DEPRECATIONS` environment variable for noisy CI).
3. The deprecated form remains functional for the entire `1.x` line. A feature deprecated in any `1.X` release continues to work in every subsequent `1.X+N` release.
4. The earliest release that may remove the feature is the next major (`2.0`), per the SemVer table above.
5. Each removal is recorded in the CHANGELOG under the major-release entry.

## Explicitly NOT contract

The following are not part of the versioned contract and may change in any release, including patches:

- **Mutation score values.** The score depends on the registered operator set, the operator profile, and your test suite. Adding a new operator to the `default` profile is a MINOR change (additive feature) but will shift scores. Pin both the gem version and the operator profile (`profile: default` or `profile: strict`) if you need a stable score across runs.
- **Mutation operator output text.** Operator *names* (the `operator` field in JSON output, e.g. `arithmetic_replacement`) are part of the contract. The exact mutated source string an operator emits is diagnostic and may change to fix bugs or improve clarity.
- **Internal classes** (anything tagged `@api private`, plus everything not listed in `docs/public_api.md`).
- **Log lines, progress output, and human-readable report wording.**
- **Performance characteristics** (timing, memory, parallel scheduling). Improvements ship in any release; regressions are bugs but not contract violations.

## Upgrading

- **Patch (`1.X.Y` → `1.X.Y+1`)** and **minor (`1.X` → `1.X+1`)**: drop in. Read the CHANGELOG for new flags or config keys you may want to opt into.
- **Major (`1.X` → `2.0`)**: a migration guide ships with the release, listing every removed contract surface and the replacement path.

## References

- [CHANGELOG](../CHANGELOG.md) — chronological list of changes per release.
