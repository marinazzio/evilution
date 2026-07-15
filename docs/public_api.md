# Public API

This document defines evilution's public, SemVer-governed surface for `1.x`.

## There is no public Ruby API

**The entire `Evilution::` Ruby namespace is internal.** Every class, module,
method, and constant under `Evilution::` may change, move, or disappear in any
release — including patch releases — with no deprecation cycle. Do not `require`
evilution and call into it programmatically expecting stability; internal
refactors will break you without warning.

Evilution is consumed through its CLI, its configuration file, its session
output, and its MCP tools — not as a library you embed. The classes are marked
`@api private` for YARD, and the top-level `Evilution` module carries the same
marker.

## What *is* the public contract

These surfaces are stable under the [versioning policy](versioning.md). They are
the supported way to drive evilution:

| Surface | Authoritative reference |
|---|---|
| **CLI commands and flags** | README "Command Reference" |
| **`.evilution.yml` configuration keys** | README "Configuration" |
| **Session JSON files** (`.evilution/results/*.json`) | README "JSON Output Schema" |
| **MCP tool schemas** (`evilution-mutate`, `evilution-session`, `evilution-info`) | README "MCP Server" → "Contract stability" |
| **Process exit codes** (`0` pass, `1` fail, `2` error) | README "Exit Codes" |
| **Hook events and payload keys** (configured via the `hooks:` config key) | README "Configuration" / hooks docs |

Anything not in that table — and in particular anything reachable only by calling
Ruby methods on `Evilution::` objects — is internal.

## Why no Ruby API at 1.0

Evilution's job is to run mutation testing from the command line (and from an MCP
agent). The value users depend on is the behaviour of `evilution run`, the shape
of the report it writes, and the config that tunes it — none of which requires a
frozen object graph. Keeping the Ruby internals unfrozen lets the isolation,
parallelism, and mutation-operator internals evolve freely across `1.x` without
spending major-version budget. If a genuine embedding use case emerges, a small
public facade can be introduced additively in a MINOR release.

## See also

- [Versioning & Upgrade Policy](versioning.md) — what each SemVer bump covers and
  how deprecations work.
