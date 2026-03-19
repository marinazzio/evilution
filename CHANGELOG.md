# Changelog

## [0.9.0] - 2026-03-19

### Added

- **ReceiverReplacement operator** — new mutation operator that drops explicit `self` receiver from method calls (e.g. `self.foo` → `foo`); catches untested self-dispatch semantics
- **Class-level `--target` filtering** — `--target Foo` now matches all methods in the `Foo` class, not just `Foo#method`; instance method targeting (`Foo#bar`) continues to work as before
- **Incremental mode** (`--incremental`) — caches killed/timeout results keyed by file content SHA256 + mutation fingerprint; skips re-running unchanged mutations on subsequent runs; atomic file-based cache in `tmp/evilution_cache/`
- **Scope-aware spec resolution** — `SpecResolver` now walks up the directory tree when an exact spec file isn't found (e.g. `app/models/game/round.rb` → `spec/models/game_spec.rb`); works with both stripped (`spec/`) and kept (`spec/lib/`) layouts

### Changed

- **MCP tool response trimming** — diffs are stripped from killed and neutral mutation entries to reduce context window usage (~36% smaller responses); survived, timed_out, and errors retain full diffs for actionability

## [0.8.0] - 2026-03-19

### Added

- **BlockRemoval operator** — new mutation operator that removes blocks from method calls (e.g. `items.map { |x| x * 2 }` → `items.map`); catches untested block logic
- **ConditionalFlip operator** — new mutation operator that flips `if` to `unless` and vice versa (e.g. `if cond` → `unless cond`); skips ternaries and `elsif` branches; catches single-branch conditional testing
- **RangeReplacement operator** — new mutation operator that swaps inclusive/exclusive ranges (e.g. `1..10` → `1...10` and vice versa)
- **RegexpMutation operator** — new mutation operator that replaces regexp patterns with a never-matching pattern (`/a\A/`), preserving flags; catches untested regex matching

## [0.7.0] - 2026-03-19

### Added

- **ArgumentRemoval operator** — new mutation operator that removes individual arguments from method calls with 2+ positional args (e.g. `foo(a, b, c)` → `foo(b, c)`, `foo(a, c)`, `foo(a, b)`)
- **Memory observability** — verbose mode (`-v`) now logs RSS and GC stats (heap_live_slots, allocated, freed) after each phase and per-mutation; includes child_rss and memory delta when available
- **Peak memory reporting** — text and JSON output include peak memory usage across all mutations
- **`rake memory:check`** — standalone memory leak detection task for pre-release validation; runs 4 checks (InProcess, Fork, mutation generation, parallel pool) and exits non-zero on regression; configurable via `MEMORY_CHECK_ITERATIONS` and `MEMORY_CHECK_MAX_GROWTH_KB` env vars
- **Neutral mutation detection** — baseline test suite run detects pre-existing failures; mutations in already-failing code are marked `neutral` instead of `survived`

### Fixed

- **Memory leak: source string retention** — `Mutation#strip_sources!` caches the diff then nils out original/mutated source strings after execution, allowing GC to reclaim them
- **Memory leak: AST node retention** — `Subject#release_node!` releases Prism AST nodes after mutation generation; nodes are no longer retained through the results chain
- **Memory leak: StringIO buffer growth** — InProcess isolation now redirects output to `/dev/null` instead of accumulating in unbounded StringIO buffers
- **Memory leak: Marshal payload bloat** — parallel pool workers now serialize only compact result hashes (status, duration, metrics) instead of full MutationResult objects with embedded Mutation/Subject/AST trees
- **Memory leak: double forking** — parallel mode uses InProcess isolation inside pool workers to avoid fork-inside-fork; sequential mode continues using Fork isolation

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
