# Changelog

## [0.6.0] - 2026-03-17

### Added

- **`--stdin` flag** — read target file paths from stdin (one per line), enabling piped workflows like `git diff --name-only | evilution run --stdin --format json`; supports line-range syntax (e.g. `lib/foo.rb:15-30`); errors if combined with positional file arguments
- **MCP server** (`evilution mcp`) — Model Context Protocol server for direct AI agent integration via stdio; exposes an `evilution-mutate` tool that accepts target files, options, and returns structured JSON results
- **MethodCallRemoval operator** — new mutation operator that removes method calls while keeping the receiver (e.g. `obj.foo(x)` → `obj`); catches untested side effects and return values

## [0.5.0] - 2026-03-16

### Added

- **Parallel execution** (`--jobs N` / `-j N`) — re-introduces parallel mutation execution using a process-based pool; each mutation runs in its own fork-isolated child process; fail-fast is checked between batches
- **Per-mutation spec targeting** — automatically resolves the matching spec file for each mutated source file using convention-based resolution; falls back to the full suite if no match; `--spec` flag overrides auto-detection
- **Progress indicator** — prints `mutation 3/19 killed` progress to stderr during text-mode runs so long-running sessions no longer appear stuck; only shown when stderr is a TTY, suppressed in quiet and JSON modes

### Fixed

- **`--version` flag** — now correctly outputs the gem version instead of "version unknown"
- **RSpec noise suppression** — child process stdout/stderr is redirected to `/dev/null` so RSpec warnings no longer corrupt JSON output or flood the terminal

## [0.4.0] - 2026-03-16

### Added

- **`--fail-fast` flag** — stop after N surviving mutants (`--fail-fast`, `--fail-fast=3`, `--fail-fast 5`); defaults to 1 when given without a value
- **Structured JSON error responses** — errors in `--format json` mode now output structured JSON with `type`, `message`, and optional `file` fields
- **Convention-based spec file resolution** — automatically maps source files to their spec counterparts (`lib/` → `spec/`, `app/` → `spec/`)
- **`test_command` in mutation result JSON** — each mutation result now includes the RSpec command used, for easier debugging
- **Auto-detect changed files from git merge base** — when no explicit files are given, Evilution automatically finds changed `.rb` files under `lib/` and `app/` since the merge base with `main`/`master` (including `origin/` remotes for CI)

### Changed

- Error classes (`ConfigError`, `ParseError`) now support a `file:` keyword for richer error context

## [0.3.0] - 2026-03-13

### Added

- **Sandbox-based temp directory cleanup** — leaked temp directories from timed-out children are now reliably cleaned up
- **Graceful timeout handling** — sends SIGTERM with a grace period before SIGKILL on child timeout

### Changed

- Default per-mutation timeout increased from 10s to 30s
- Parent process now restores the original source file after each mutation (defense-in-depth)

## [0.2.0] - 2026-03-10

### Added

- **Line-range targeting** — scope mutations to exact lines: `lib/foo.rb:15-30`, `lib/foo.rb:15`, `lib/foo.rb:15-`
- **Method-name targeting** (`--target`) — mutate a single method by fully-qualified name (e.g. `Foo::Bar#calculate`)
- **Commands section** in `--help` output

### Changed

- Added `changelog_uri` to gemspec metadata
- Added GitHub publish workflow

### Deprecated

- **`--diff` flag** — use line-range targeting instead
- **Coverage-based filtering flags/config** (`--no-coverage` flag and `coverage` config key) — deprecated and now ignored; coverage-based filtering behavior has been removed from `Runner`

### Removed

- **Parallel execution** (`--jobs` flag) — simplifies codebase for AI-agent-first design; will be reintroduced later
- **File-discovery logic** from `Integration::RSpec` — spec files are now passed explicitly or default to `spec/`

## [0.1.0] - 2026-03-02

### Added

- **18 mutation operators**: ArithmeticReplacement, ComparisonReplacement, BooleanOperatorReplacement, BooleanLiteralReplacement, NilReplacement, IntegerLiteral, FloatLiteral, StringLiteral, ArrayLiteral, HashLiteral, SymbolLiteral, ConditionalNegation, ConditionalBranch, StatementDeletion, MethodBodyReplacement, NegationInsertion, ReturnValueRemoval, CollectionReplacement
- **Prism-based AST parsing** with source-level surgery via byte offsets
- **Fork-based isolation** for safe mutation execution
- **RSpec integration** for test execution
- **Parallel execution** with configurable worker count (`--jobs`)
- **Diff-based targeting** to mutate only changed code (`--diff HEAD~1`)
- **Coverage-based filtering** — skip mutations on lines no test exercises
- **JSON output** for AI agents and CI pipelines (`--format json`)
- **CLI output** with human-readable mutation testing results
- **Actionable suggestions** for surviving mutants
- **Configuration file** support (`.evilution.yml`)
- **`evilution init`** command to generate default config
- **Error handling** with clean exit codes (0=pass, 1=fail, 2=error)
