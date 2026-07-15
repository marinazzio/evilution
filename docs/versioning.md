# Versioning & Upgrade Policy

This document defines what `evilution` promises across releases.

## SemVer interpretation (1.x)

| Bump          | Triggered by                                                                 |
|---------------|-------------------------------------------------------------------------------|
| MAJOR (`2.0`) | Removing or renaming anything in the public contract; changing semantics; tightening input validation. |
| MINOR (`1.X`) | Adding a new CLI flag, config key, mutation operator, or session/MCP field; introducing a public Ruby facade where none exists today; relaxing validation; adding an operator to the `default` profile (whether brand-new or promoted from `strict`). |
| PATCH (`1.X.Y`) | Bug fix, performance improvement, documentation, internal refactor with no observable contract effect. |

## Public contract surface

The following surfaces are covered by the SemVer guarantees above:

- **Public Ruby API** — there is none. The entire `Evilution::` namespace is internal and may change in any release. See [docs/public_api.md](public_api.md).
- **CLI flags and commands** — the README "Command Reference" tables are the authoritative list.
- **`.evilution.yml` configuration keys** — see the README "Configuration" section.
- **Session JSON files** (`.evilution/results/*.json`) — see the README "JSON Output Schema" section.
- **MCP tool input/output schemas** (`evilution-mutate`, `evilution-session`, `evilution-info`) — see the README "MCP Server" section.
- **Process exit codes** — `0` pass, `1` fail, `2` error. Documented in the README "Exit Codes" section.

Anything not on this list is internal. It can change in any release without a deprecation cycle.

## Deprecation cycle

When a feature on the public contract surface is deprecated:

1. It is marked with a deprecation note in the relevant doc table (CLI flags, config keys, session/MCP fields).
2. Where the call site is reachable at runtime, a one-line warning is emitted to stderr.
3. The deprecated form remains functional for the entire `1.x` line. A feature deprecated in any `1.X` release continues to work in every subsequent `1.X+N` release.
4. The earliest release that may remove the feature is the next major (`2.0`), per the SemVer table above.
5. Each removal is recorded in the CHANGELOG under the major-release entry.

## Explicitly NOT contract

The following are not part of the versioned contract and may change in any release, including patches:

- **Mutation score values.** The score depends on the registered operator set, the operator profile, and your test suite. Adding a new operator to the `default` profile is a MINOR change (additive feature) but will shift scores. Pin both the gem version and the operator profile (`profile: default` or `profile: strict`) if you need a stable score across runs.
- **Mutation operator output text.** Operator *names* (the `operator` field in JSON output, e.g. `arithmetic_replacement`) are part of the contract. The exact mutated source string an operator emits is diagnostic and may change to fix bugs or improve clarity.
- **Internal classes** (any class not explicitly documented as part of the public Ruby API).
- **Log lines, progress output, and human-readable report wording.**
- **Performance characteristics** (timing, memory, parallel scheduling). Improvements ship in any release; regressions are bugs but not contract violations.

## Upgrading

- **Patch (`1.X.Y` → `1.X.Y+1`)** and **minor (`1.X` → `1.X+1`)**: drop in. Read the CHANGELOG for new flags or config keys you may want to opt into.
- **Major (`1.X` → `2.0`)**: a migration guide ships with the release, listing every removed contract surface and the replacement path.

## References

- [CHANGELOG](../CHANGELOG.md) — chronological list of changes per release.
