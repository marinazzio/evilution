# Changelog

## [0.16.1] - 2026-03-30

### Fixed

- **Critical: SourceSurgeon crashes on multi-byte UTF-8 source files** — `SourceSurgeon.apply` used `String#[]=` with Prism byte offsets, but Ruby interprets indices as character offsets for UTF-8 strings, causing `IndexError` on files containing non-ASCII characters (Cyrillic, CJK, emoji). Fixed by operating on ASCII-8BIT binary encoding before restoring original encoding (#434)

## [0.16.0] - 2026-03-29

### Added

- **Variable mutation operators** — `LocalVariableAssignment`, `InstanceVariableWrite`, `ClassVariableWrite`, `GlobalVariableWrite` replace variable assignments with `nil` to test whether stored values are actually used (#394, #395, #396, #397)
- **Rescue/ensure mutation operators** — `RescueRemoval` removes rescue clauses, `RescueBodyReplacement` replaces rescue bodies with `nil`, `InlineRescue` removes inline `rescue` fallback values, `EnsureRemoval` removes ensure blocks (#399, #400, #401, #402)
- **Loop control mutation operators** — `BreakStatement`, `NextStatement`, `RedoStatement` remove loop control flow statements to test whether early exits and restarts are necessary (#404, #405, #406)
- **BangMethod operator** — swaps bang methods with their non-bang counterparts (`sort!` → `sort`, `map!` → `map`, etc.) to test whether in-place mutation semantics matter (#413)
- **Bitwise mutation operators** — `BitwiseReplacement` swaps `&`, `|`, `^` with each other; `BitwiseComplement` removes `~` or swaps it with unary minus (#416, #417)
- **Super call mutation operators** — `ZsuperRemoval` replaces implicit `super` with `nil`; `ExplicitSuperMutation` removes arguments, removes individual arguments, or replaces `super(args)` with implicit `super` (#419, #420)
- **CollectionReplacement expansions** — added method swap pairs: `pop`/`shift`, `push`/`unshift`, `each_key`/`each_value`, `assoc`/`rassoc`, `grep`/`grep_v`, `take`/`drop`, `min`/`max`, `min_by`/`max_by`, `compact`/`flatten`, `zip`/`product`, `first`/`last`, `keys`/`values` (#407, #408, #409, #410, #411, #412)
- **SendMutation expansions** — enumerable reduction method swaps (`reduce`/`inject`, `sum`/`count`, `tally`/`group_by`, etc.) and conversion method swaps (`to_s`/`to_i`/`to_f`/`to_a`/`to_h`) (#414, #415)
- **Suggestion templates** — concrete RSpec suggestion templates for variable mutations, rescue/ensure mutations, bitwise mutations, and super call mutations (#398, #403, #418, #421)
- **TTY progress bar** — real-time progress display showing `[=====>    ] 45/100 mutations | 38 killed | 2 survived | 00:23 elapsed | ~00:28 remaining`; TTY-aware rendering (carriage return for TTY, newlines for piped output); integrated into Runner for both sequential and parallel execution (#422, #423)
- **`--no-progress` flag** — CLI flag and config option to disable the progress bar for CI/piped environments (#424)

### Changed

- **Operator count** — 46 operators (up from 30), covering variables, rescue/ensure, loop control, bang methods, bitwise operators, and super calls
- **Runner refactoring** — extracted `notify_result` method for unified result callbacks, progress bar updates, and diagnostic logging across sequential and parallel execution modes

## [0.15.0] - 2026-03-29

### Added

- **SuperclassRemoval operator** — mutates `class Foo < Bar` to `class Foo` (removes inheritance) to test whether the superclass is actually needed (#342)
- **MixinRemoval operator** — removes `include`, `extend`, and `prepend` statements individually to test whether each mixin is actually used; supports both class and module scopes (#343)
- **Suggestion templates for class/module mutations** — static and concrete RSpec suggestion templates for `superclass_removal` and `mixin_removal` operators (#344)
- **Namespace wildcard matching** (`Foo::Bar*`) — `--target` now supports trailing `*` to match all classes under a namespace prefix (#329)
- **Method-type selectors** (`Foo#`, `Foo.`) — `--target` now supports `Foo#` for all instance methods and `Foo.` for all class methods; class methods (`def self.foo`) are now captured by the parser with `.` separator (#332)
- **Descendant matching** (`descendants:Foo`) — `--target` now supports inheritance-based filtering via `Evilution::AST::InheritanceScanner` Prism visitor (#335)
- **Source glob matching** (`source:lib/**/*.rb`) — `--target` now supports file glob patterns (#338)
- **CommentMarking heuristic** — `# evilution:equivalent` inline comment marks mutations as equivalent (#384)
- **ArithmeticIdentity heuristic** — detects equivalent mutations for arithmetic identity operations like `x + 0`, `x * 1`, `x ** 1` (#383)
- **AliasSwap heuristic expansion** — added `count`/`length` and `detect`/`find` alias pairs for `collection_replacement` operator (#384)

### Changed

- **Operator count** — 30 operators (up from 28), with new structural mutation operators for class/module definitions
- **Parse tree caching** — shared parse cache on `Mutator::Base` for structural operators, cleared after each run to prevent unbounded memory growth
- **Class method support in parser** — `AST::Parser` now distinguishes instance methods (`Foo#bar`) from class methods (`Foo.bar`) via Prism's `DefNode#receiver`
- **Descendant filter** — uses `/[#.]/` split to include both instance and class methods in inheritance-based matching

## [0.14.0] - 2026-03-28

### Added

- **Session result storage** (`--save-results`) — persist mutation run results as timestamped JSON files under `.evilution/results/`; enables cross-run comparison and history browsing (#298)
- **`evilution session list`** — CLI command to list saved session results with timestamps, scores, and mutation counts (#302)
- **`evilution session show`** — CLI command to display detailed session results including per-file mutation breakdown (#306)
- **`evilution session gc`** — CLI command for garbage collection of old session results; supports `--keep` flag to control retention count (#310)
- **MCP session history tools** — `evilution-session-list` and `evilution-session-show` MCP tools for AI agent browsing of session history (#353)
- **MCP cross-run diff tool** (`evilution-session-diff`) — compares two sessions and returns fixed mutations, new survivors, and persistent survivors (#354)
- **MCP streaming test suggestions** — survived mutations stream concrete RSpec suggestions via MCP progress notifications during execution (#355)

### Changed

- **Compact class/module style** — all class and module declarations switched to compact style (e.g. `class Evilution::Session::Store`); intermediate module files added for standalone loading (#359)
- **Dependency updates** — mcp 0.9.0 → 0.9.1 (#375), rubocop 1.85.1 → 1.86.0 (#376)

## [0.13.0] - 2026-03-23

### Added

- **CompoundAssignment operator** — new mutation operator for compound assignment expressions; swaps arithmetic (`+=` ↔ `-=`, `*=` ↔ `/=`, `%=` → `*=`, `**=` → `*=`), bitwise (`&=` ↔ `|=`/`^=`, `<<=` ↔ `>>=`), and logical (`&&=` ↔ `||=`) compound assignments; also generates removal mutations (statement → `nil`); covers local, instance, class, and global variables (#234, #236, #239, #243)
- **Compound assignment suggestion templates** — concrete RSpec `it`-block suggestions for survived compound assignment mutations via `--suggest-tests` (#247)

### Changed

- **Operator count** — 28 operators (up from 27), increasing mutation density for real-world Ruby code
- **Refactored IntegerLiteral mutation logic** and updated RuboCop configuration (#360)

## [0.12.0] - 2026-03-22

### Added

- **Concrete RSpec test suggestions** (`--suggest-tests`) — surviving mutants now include ready-to-use RSpec `it` blocks instead of generic guidance; covers all operator families: arithmetic, comparison, boolean, literal, collection, conditional, structural, and nil operators (#209, #215, #216, #217, #218, #219, #220, #221)
- **MCP tool `suggest_tests` parameter** — enables concrete test suggestions in MCP tool responses (#213)

### Changed

- **RuboCop configuration cleanup** — added metrics targets and refactored cop values/exclusions (#204, #207)

## [0.11.0] - 2026-03-21

### Added

- **Nil variants for literal operators** — BooleanLiteralReplacement, IntegerLiteralReplacement, FloatLiteralReplacement, StringLiteralReplacement, and SymbolLiteralReplacement now produce a `nil` mutation alongside their existing replacements (#193)
- **NilReplacement expansion** — `nil` now mutates to `true`, `false`, `0`, and `""` (was only `true`); covers boolean, numeric, and string contexts (#197)
- **CollectionReplacement expansion** — added 8 new method swaps: `sort`↔`sort_by`, `find`↔`detect`, `any?`↔`all?`, `count`↔`length` (14 total swaps, up from 6) (#198)
- **ComparisonReplacement expansion** — added opposite direction flips: `>`↔`<`, `>=`↔`<=` alongside existing boundary and equality mutations (#199)
- **RegexpMutation expansion** — added always-matching `/.*/` variant alongside the existing never-matching `/a\A/`; each regexp now produces 2 mutations (#200)
- **ArithmeticReplacement expansion** — added bitwise shift operators `<<`↔`>>` (#189)
- **MCP verbosity control** — MCP tool responses support configurable verbosity levels (#192)

### Changed

- **Dependency updates** (#191)

## [0.10.0] - 2026-03-21

### Added

- **SendMutation operator** — new mutation operator that replaces method calls with semantically related alternatives (e.g. `detect` ↔ `find`, `map` ↔ `flat_map`, `length` ↔ `size`, `gsub` ↔ `sub`, `send` ↔ `public_send`, and more); 17 replacement pairs covering common Ruby method families
- **ArgumentNilSubstitution operator** — new mutation operator that replaces each positional argument with `nil` one at a time (e.g. `foo(a, b)` → `foo(nil, b)`, `foo(a, nil)`); skips splat, keyword, block, and forwarding arguments
- **HTML report** (`--format html`) — self-contained HTML mutation report with dark theme, color-coded mutation map, survived mutation diffs with suggestions, and score badge; written to `evilution-report.html`
- **Equivalent mutation detection** — automatically identifies mutations that produce semantically identical behavior using four heuristics: noop source (identical before/after), method body nil (empty/nil methods), alias swap (detect↔find, length↔size, collect↔map), and dead code (unreachable statements after return/raise); equivalent mutations are excluded from the mutation score denominator
- **MCP tool equivalent trimming** — diffs are stripped from equivalent mutation entries in MCP responses alongside killed and neutral entries

### Removed

- **`--diff` CLI flag** — deprecated since v0.2.0; use line-range targeting instead (e.g. `evilution run lib/foo.rb:15-30`)
- **`--no-coverage` CLI flag** — deprecated since v0.2.0; had no effect
- **`diff_base` and `coverage` config keys** — no longer recognized in `.evilution.yml`; config file warnings removed
- **`Diff::Parser` and `Diff::FileFilter` modules** — dead code removed along with specs
- **`Coverage::Collector` and `Coverage::TestMap` modules** — dead code removed along with specs

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
