# Changelog

## [0.22.7] - 2026-04-13

### Fixed

- **Rails 8 models with `enum`: every mutation errors with `ArgumentError`** — re-running the class body via `load`/`require` retriggered Rails 8's `detect_enum_conflict!` because the enum's predicate methods already existed from the first load, so mutations scored 0% on any affected file; now `remove_defined_constants` drops constants defined by the mutated source (via `remove_const` on the parent namespace) before re-loading, so the class body runs on a fresh constant and DSLs with conflict detection (enum, and any future DSL with redefinition guards) see a clean slate (#683)

## [0.22.6] - 2026-04-12

### Fixed

- **Zeitwerk re-autoloads original file during mutation load** — Zeitwerk's `const_added` hook re-autoloaded the original source when a module constant was reopened from a temp-dir copy, re-setting `@_included_block` after `clear_concern_state` already removed it; now `pin_autoloaded_constants` resolves all module/class constants from the source via `Object.const_get` before loading, preventing the autoloader from re-triggering (#680)

## [0.22.5] - 2026-04-12

### Fixed

- **`ActiveSupport::Concern` modules: all mutations error with `MultipleIncludedBlocks`** — re-evaluating a mutated concern file triggered Rails' guard because `@_included_block` (and `@_prepended_block`) was already set from the original load with a different `source_location`; now `clear_concern_state` removes these instance variables from affected concern modules before `require`/`load`, matching both original file paths and temp-dir copies via subpath suffix so consecutive mutations of the same concern also succeed (#676, PR #678)

## [0.22.4] - 2026-04-12

### Fixed

- **`LoadError: cannot load such file -- spec_helper` during preload** — `perform_preload` ran before `ensure_framework_loaded`, so `spec/` was not on `$LOAD_PATH` and `rspec/core` was not loaded when `rails_helper.rb` tried to `require 'spec_helper'` and call `RSpec.configure`; now `prepare_load_path_for_preload` adds `spec/` to `$LOAD_PATH` and loads `rspec/core` before the preload file; errors (e.g. missing `rspec-core` gem) propagate as `ConfigError` with clear context (#669, #673)

## [0.22.3] - 2026-04-12

### Fixed

- **`LoadError: cannot load such file -- spec_helper`** — projects with `--require spec_helper` in `.rspec` failed on every mutation because `spec/` was not on `$LOAD_PATH`; RSpec's CLI normally adds it, but evilution calls `RSpec::Core::Runner.run` directly, bypassing the CLI; now adds `spec/` to `$LOAD_PATH` in `ensure_framework_loaded`, `baseline_runner`, and `perform_preload`; also loads `rspec/core` before preloading so that `spec_helper.rb` can use `RSpec.configure` (#669)

## [0.22.2] - 2026-04-12

### Added

- **Rails-aware isolation auto-selection** — `isolation: :auto` (the default) now detects Rails projects by walking up from target files looking for `config/application.rb`; when Rails is detected, isolation resolves to `:fork` instead of `:in_process`, preventing indefinite hangs caused by Rails' `Thread.handle_interrupt(Exception => :never)` masking `Timeout.timeout`'s `Thread#raise` (#662, #663, PR #665)
- **Parent-process preload for fork isolation** — new `--preload FILE` / `--no-preload` CLI flags and `preload:` config key; when fork isolation is active on a Rails project, evilution auto-detects and preloads `spec/rails_helper.rb` or `test/test_helper.rb` in the parent process so forked children inherit the loaded framework via copy-on-write, eliminating per-mutation Rails boot cost (#662, PR #665)
- **`Evilution::RailsDetector` module** — lightweight filesystem-only detection of Rails roots with memoized cache and thread-safe mutex; used by both isolation resolution and preload auto-detection (#662, PR #665)
- **Isolation strategy documentation** — `docs/isolation.md` explains the three strategies, the `handle_interrupt` hazard, and preload configuration (#662, PR #665)

### Fixed

- **`run_mutations_parallel` ignoring `--isolation`** — parallel mode hardcoded `Isolation::InProcess.new` for its worker isolator, silently overriding `config.isolation`; now uses `build_isolator` so `--jobs N --isolation fork` correctly uses fork per-mutation inside workers (#663, PR #665)
- **Rails detection failing for auto-resolved targets** — `detected_rails_root` used `config.target_files` which is empty in git-changed or source-glob modes; now uses memoized `resolve_target_files` so Rails is detected regardless of how targets were specified (PR #665)
- **`SyntaxError` in preload file escaping rescue** — `perform_preload` rescued `LoadError, StandardError` but `SyntaxError` is a `ScriptError` (not `StandardError`); now rescues `ScriptError, StandardError` (PR #665)
- **Isolator built eagerly before targets resolved** — `build_isolator` ran in `initialize` before `resolve_target_files`; now lazy-initialized on first use, ensuring Rails detection has resolved targets available (PR #665)

### Changed

- **Isolation warning for explicit `in_process` under Rails** — when a user explicitly passes `--isolation in_process` on a detected Rails project, evilution emits a one-shot stderr warning about the `handle_interrupt` hang hazard and proceeds; suppressed by `--quiet` (#662, PR #665)

## [0.22.1] - 2026-04-10

### Added

- **Error class and backtrace capture** — `MutationResult` now stores `error_class` and `error_backtrace` alongside `error_message`; the backtrace array is duplicated and frozen to keep results immutable; both fields are threaded through `Isolation::Fork` (Marshal-safe across the IPC pipe), `Isolation::InProcess`, and the runner's `compact_result` / `rebuild_results` path (#648, PR #659)
- **Verbose error diagnostics** — `--verbose` now logs error class, message, and the first 5 backtrace lines for errored mutations (previously `--verbose` only showed memory/GC stats, leaving errors invisible) (#648, PR #659)
- **Error details in JSON reports** — JSON reporter output includes `error_class` and `error_backtrace` fields under `errors[]` entries when present, so downstream tools (CI, MCP consumers) can surface failure causes without re-running (#648, PR #659)

### Fixed

- **Silent load-time crashes in `Isolation::Fork`** — mutations that raised non-`SyntaxError` script errors at load time (e.g. `NoMethodError: super called outside of method`) escaped `Integration::Base`'s narrow rescue and either surfaced cryptically or went silent under fork isolation; both isolators now rescue `ScriptError, StandardError` as a safety net and report them as `:error` status with full class and backtrace (#646, PR #656)
- **`symbol_literal` operator breaking keyword arguments** — mutating symbols in label form (`foo:` inside hash literals or keyword arguments) produced invalid Ruby source; the operator now detects label-form symbols via Prism's `closing_loc` and skips them, only mutating standalone symbol literals (`:foo`) (#647, PR #657)
- **Syntax errors in mutated source crashing in-process runs** — `Integration::Base#apply_mutation` now captures `SyntaxError` during `require`/`load` and returns a structured error result instead of propagating the exception up through `call`; error results include the error class and backtrace for diagnosis (#644, #645, PR #653, PR #655)

### Changed

- **Integration::Base refactor** — `apply_mutation` split into `apply_via_require` and `apply_via_load` helpers; rescue scope moved from `#call` to `#apply_mutation` so load-time errors return a result hash while abstract-method `NotImplementedError`s still propagate as intended

## [0.22.0] - 2026-04-09

### Added

- **Minitest integration** — full Minitest support as an alternative to RSpec; abstract `Integration::Base` framework with template method pattern; `Integration::Minitest` with programmatic `Minitest.__run` execution, `MinitestCrashDetector` reporter for distinguishing assertion failures from crashes; `--integration minitest` CLI flag and `integration: minitest` config option; `SpecResolver` parameterized for Minitest file discovery (`test/`, `_test.rb`); plugin-based runner dispatch via `INTEGRATIONS` registry; baseline runner abstracted from RSpec with injectable runner callable; Minitest concrete suggestion templates using `def test_`/`assert_equal` style (#223, #224, #225, #226, #227, #228, #229, #230)
- **New mutation operators (3)** — `index_to_at` replaces `arr[0]` with `arr.at(0)` for array index access (#618); `regex_simplification` simplifies regex character classes and quantifiers (#514); `block_pass_removal` removes block arguments (`&...`) in method calls (#619)
- **Mutation density benchmarking** — comparison tools and methodology for measuring mutation density against reference tool; baseline results and operator classification documents (#523, #526, #541)

### Fixed

- **Multi-byte character offset bug** — Prism byte offsets were used with character-based `String#[]`, causing garbled source extraction for files with multi-byte characters (UTF-8 Cyrillic, Thai, CJK, etc.); fixed `AST::Parser`, `DisableComment`, and 7 mutation operators to use `byteslice`/`getbyte`; added `byteslice_source` helper to `Mutator::Base` (#615)

### Changed

- **Operator count** — 72 operators (up from 69), with new index-to-at, regex simplification, and block pass removal operators
- **Test framework support** — RSpec and Minitest both supported; documentation updated throughout CLI help, MCP tool descriptions, and README

## [0.21.0] - 2026-04-08

### Added

- **Heredoc-aware string mutations** — `string_literal` operator now skips literal text in heredocs (all variants: `<<HEREDOC`, `<<-HEREDOC`, `<<~HEREDOC`, `<<~'HEREDOC'`); still mutates string literals inside interpolated expressions (`#{"literal"}`); uses Prism's built-in `heredoc?` detection (#522, #545, #546, #547)
- **`--skip-heredoc-literals` CLI flag** — completely suppresses all string literal mutations inside heredocs, including strings within interpolated expressions; configurable via CLI flag and `.evilution.yml` (#548)
- **Temp-file mutation approach** — mutations are applied to temporary file copies instead of overwriting original source files; uses load-path redirection (`$LOAD_PATH.unshift`) so `require` resolves the mutated copy; original files are never modified during mutation runs (#537)
- **Zeitwerk-compatible load-path redirection** — forked test processes redirect the load path to pick up mutated temp files, compatible with Zeitwerk-like autoloaders (#550, #551)
- **Temp directory cleanup and tracking** — `TempDirTracker` ensures mutation temp directories are cleaned up after each run, preventing temp file accumulation (#552)
- **Integration tests for temp-file mutation** — end-to-end tests verifying original file protection, temp file cleanup, and sandbox isolation during forked mutation runs (#554)
- **Integration tests for heredoc mutation behavior** — full-pipeline tests covering plain, squiggly, non-squiggly, dash, single-quote, interpolated, nested, and mixed heredocs (#549)

### Changed

- **Mutation isolation** — mutation runs no longer modify original source files on disk; all mutations are applied to temporary copies, improving safety for concurrent usage and editor integration
- **Operator options threading** — `Registry#mutations_for` accepts `operator_options` hash, passed through to operator constructors; enables per-operator configuration like `skip_heredoc_literals`
- **Dependencies** — bumped `mcp` gem to 0.11.0; bumped `ruby/setup-ruby` CI action to 1.300.0

## [0.20.0] - 2026-04-08

### Added

- **New mutation operators (10)** — `loop_flip` swaps `while`↔`until` loops (#581); `string_interpolation` replaces `#{expr}` content with `nil` (#582); `retry_removal` removes `retry` statements from rescue blocks (#583); `case_when` removes `when` branches, replaces bodies with `nil`, removes `else` (#584); `predicate_replacement` replaces predicate method calls (`foo?`) with `true`/`false` (#585); `equality_to_identity` converts `a == b` to `a.equal?(b)` (#586); `lambda_body` replaces lambda/proc bodies with `nil` (#588); `begin_unwrap` removes bare `begin..end` wrappers (#589); `block_param_removal` removes `&block` parameters from method definitions (#590)
- **Method body replacement expansion** — `method_body_replacement` now generates `self` and `super` replacements alongside `nil` (#587)
- **SendMutation expansions** — added `downcase`↔`upcase` (#594), `strip`→`lstrip`/`rstrip`, `lstrip`→`strip`, `rstrip`→`strip`, `chomp`↔`chop` (#595) method swap pairs
- **Coverage gap detection and reporting** — survived mutations are grouped by `(file, subject, line)` into coverage gaps; reported in CLI (`N coverage gaps` header with grouped entries), JSON (`coverage_gaps` key), HTML (grouped gap entries with operator tags), and session data (#592)
- **VoidContext equivalent heuristic** — detects equivalent mutations where collection methods are swapped in void context (e.g. `each`↔`map`, `each`↔`reverse_each` when return value is unused); uses Prism AST parent-node walking (#593)
- **AliasSwap heuristic expansion** — added `count`↔`size` and `detect`↔`find` alias pairs for equivalent detection (#591)
- **Related spec heuristic** — automatically detects mutations involving `.includes()` and finds related request/integration/feature/system specs by domain name, improving test targeting for association mutations (#596)
- **Crash detection in RSpec integration** — `CrashDetector` formatter distinguishes assertion failures from runtime crashes (e.g. `NoMethodError`, `SystemStackError`); when all test failures are crashes (no assertion failures), the result includes a crash summary in the error field; reuses a single detector instance across mutation runs to avoid formatter accumulation (#597)

### Changed

- **Operator count** — 69 operators (up from 60), with new loop, string, case/when, predicate, identity, lambda, begin/end, and block parameter operators
- **Equivalent heuristic count** — 7 heuristics (up from 5), with new void context detection and expanded alias pairs

## [0.19.0] - 2026-04-07

### Added

- **Smart spec auto-detection** — `SpecResolver` maps source files to the closest matching spec using Rails conventions: controllers to request specs (`app/controllers/foo_controller.rb` → `spec/requests/foo_spec.rb`), models, services, Avo resources, and lib/ paths; falls back through parent directory patterns when exact match doesn't exist; warns when falling back to full suite so users know to use `--spec` (#530, #555)
- **`--spec-dir DIR` CLI flag** — include all `*_spec.rb` files in a directory recursively; composable with `--spec` for combining explicit files and directories (#513)
- **RSS tracking per mutation** — JSON output includes per-mutation RSS memory measurements for profiling memory behavior across mutations (#532)
- **Memory budget CI gate** — dedicated benchmark workflow with memory check step; uses realistic project classes as fixtures (#533, #567)
- **Worker hang protection** — `WorkQueue` item timeout prevents indefinite worker hangs; timeout handling for worker timing collection (#558, #559)

### Fixed

- **InProcess `suppress_output` closing `/dev/null` handle** — prevent closing the shared `/dev/null` file descriptor which caused subsequent output suppression to fail (#569)
- **Double `Process.wait` in Fork isolation** — handle empty child processes without raising (#561)

### Changed

- **RSpec integration memory management** — use clear hooks to release AST nodes and source strings between mutations, preventing memory retention across mutation runs (#543)

## [0.18.0] - 2026-04-03

### Added

- **Disable comments** — `# evilution:disable` comments to suppress mutations on specific lines, methods, or regions; inline disable for single lines, standalone disable before `def` for entire methods, range disable/enable pairs for arbitrary regions; `--show-disabled` flag reports skipped mutations in CLI, JSON, and HTML output (#321, #323, #325)
- **Sorbet `sig` filtering** — automatically detects and excludes mutations inside Sorbet `sig { ... }` blocks; cached per file for performance (#330, #334)
- **Session diff engine** — `Evilution::Session::Diff` compares two saved sessions, reporting fixed mutations, new survivors, persistent survivors, and score delta; identity matching by `[operator, file, line, subject]` (#333)
- **`session diff` CLI command** — `evilution session diff <base> <head>` with color-coded text output (green=fixed, red=new survivors, yellow=persistent) and `--format json` support (#336)
- **HTML report baseline comparison** — `--baseline-session PATH` overlays a saved session on the HTML report, highlighting regressions with badges and showing score delta (#339)
- **`util mutation` CLI command** — `evilution util mutation [-e CODE | FILE]` previews all mutations for a source file or inline Ruby snippet; supports `--format json` (#328)
- **`subjects` CLI command** — `evilution subjects [files...]` lists all mutation subjects (methods) with file locations and mutation counts; supports `--stdin` (#322)
- **`tests list` CLI command** — `evilution tests list [files...]` lists spec files mapped to source files via `SpecResolver` (#326)
- **`environment show` CLI command** — `evilution environment show` displays runtime environment: version, Ruby version, config path, and all active settings (#319)
- **Type-aware return mutation operators** — `CollectionReturn` replaces collection return values with type-aware alternatives (`[]`, `{}`); `ScalarReturn` replaces scalar return values with type-aware alternatives (`0`, `""`, `nil`) (#300, #304)
- **Keyword argument mutations** — `KeywordArgument` operator removes default values, removes optional keywords entirely, and removes `**kwargs` rest parameters (#345)
- **Multiple assignment mutations** — `MultipleAssignment` operator removes individual assignment targets and swaps 2-element order (#346)
- **Yield statement mutations** — `YieldStatement` operator removes yield, removes yield arguments, and replaces yield value with `nil` (#347)
- **Splat operator mutations** — `SplatOperator` operator removes `*` (splat) and `**` (double-splat) from method calls and array literals (#348)
- **`defined?` check mutations** — `DefinedCheck` operator replaces `defined?(expr)` with `true` (#356)
- **Regex capture reference mutations** — `RegexCapture` operator swaps numbered capture references (`$1`↔`$2`) and replaces with `nil` (#357)
- **Suggestion templates** — concrete RSpec suggestions for `collection_return` and `scalar_return` operators (#308)
- **Efficiency metrics** — summary output includes `efficiency` (killtime/wall-clock ratio), `mutations_per_second` throughput, and `killtime` aggregate; reported in CLI, JSON, and HTML (#313)
- **Parallel execution metrics** — worker statistics tracking with `busy_time`, `wall_time`, `idle_time`, and `utilization` per worker (#314)
- **Demand-driven work distribution** — `Parallel::Pool` uses pipe-based shared work queue with demand-driven dispatch and configurable prefetch; replaces batch-based distribution (#303, #307, #311)

### Changed

- **Operator count** — 60 operators (up from 52), with new return-type, keyword, assignment, yield, splat, defined?, and regex capture operators
- **CLI reporter** — survived mutations now include subject name and code diffs (#341)
- **Dependency updates** — Ruby 3.3.10 → 3.3.11 in CI (#447), ruby/setup-ruby 1.295.0 → 1.299.0, rubygems/release-gem 1.1.4 → 1.2.0

## [0.17.0] - 2026-03-30

### Added

- **Hooks system** — lifecycle hooks for mutation testing pipeline: `worker_process_start` for parallel workers, `mutation_insert_pre`/`post` for RSpec integration, `setup_integration_pre`/`post` for test setup; hook registry with registration, dispatch, and error isolation; `.evilution.yml` hooks configuration (#265, #272, #277, #282, #286, #290)
- **Index access mutation operators** — `IndexToFetch` replaces `[]` with `.fetch()`, `IndexToDig` replaces `[]` chains with `.dig()`, `IndexAssignmentRemoval` removes `[]=` assignments (#280, #283, #288)
- **Pattern matching mutation operators** — `PatternMatchingGuard` removes or negates guard clauses in `case/in` patterns; `PatternMatchingAlternative` removes, reorders alternatives in `pat1 | pat2` patterns; `PatternMatchingArray` removes or wildcards elements in array and find patterns (#293, #297, #301)
- **AST pattern language** — custom DSL for `ignore_patterns` configuration: node type matching, attribute constraints, nested patterns, wildcards (`_`, `*`, `**`), negation, and alternatives; recursive descent parser producing matcher objects; syntax spec in `docs/ast_pattern_syntax.md` (#312, #315)
- **AST pattern filter integration** — mutations matching `ignore_patterns` are skipped during generation; skipped count reported in CLI, JSON, HTML reporters and session data (#317)
- **`ignore_patterns` config** — new `.evilution.yml` key accepting an array of AST pattern strings to exclude mutations on logging/debug/infrastructure code (#320)
- **Suggestion templates** — concrete RSpec suggestions for index access mutations (`index_to_fetch`, `index_to_dig`, `index_assignment_removal`) and pattern matching mutations (`pattern_matching_guard`, `pattern_matching_alternative`, `pattern_matching_array`) (#292, #305)

### Changed

- **Operator count** — 52 operators (up from 46), with new index access, pattern matching, and hooks integration
- **Hooks wiring** — Runner passes hooks through to Fork isolator, RSpec integration, and Parallel::Pool; comprehensive test coverage for hooks lifecycle (#295)

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
