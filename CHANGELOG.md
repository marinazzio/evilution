# Changelog

Versioning policy: see [docs/versioning.md](docs/versioning.md).

## [0.31.0] - 2026-05-27

### Added

- **Proof-of-life canary at session start** — before any real mutation runs, `Evilution::Runner::Canary` evals a synthetic, guaranteed-unobservable mutation through the configured integration + isolation. A healthy pipeline must score it `:survived`; any other status aborts the run with a diagnostic, so the user never sees a score that was produced by a broken pipeline (autoload mismatch, reporter-plugin eviction, isolation defect, `fail_if_no_examples` config drift, etc.). On by default; toggle with `--[no-]canary` or `canary: true|false` in `.evilution.yml`. Mirrors the configured `--isolation` so isolation-specific defects are caught too (EV-kcuf, PR #1268, GH #1233)

### Fixed

- **Mutation children no longer pollute the working tree with files written to relative paths** — every isolator (fork and in_process) now `Dir.chdir`s into a per-mutation sandbox directory for the duration of `test_command.call`, and removes the sandbox on the way out. Any mutation that turns an absolute path into a relative one — `argument_removal` on `File.join(dir, name)`, `method_call_removal` on `File.expand_path(rel, base)`, etc. — used to write `File.write(name, …)` into the parent process's CWD (typically the repo root) and leak past the run; baselining `lib/evilution/runner/canary.rb` deposited 43 stray files (`canary_<pid>_<hex>_spec.rb`, `evilutioncanary_<pid>_<hex>.rb`) before this fix. Spec resolution and source eval anchor project-relative paths to `Evilution::PROJECT_ROOT` (captured at load), so the sandbox CWD does not break `SpecResolver`, `SpecSelector`, `MutationApplier`, `SourceEvaluator`, or the `RSpec::Core::Runner` / `Minitest.load` invocation sites (EV-wqxu, PR #1281, GH #1278)
- **`MutationApplier` registers the mutation in `$LOADED_FEATURES` BEFORE evaluating the source, not after** — a sibling `require_relative` chain that loops back to the mutated file during the eval itself (e.g. `lib/evilution/mcp/*.rb` tools whose body requires a peer that requires this file back) re-read the *original* source from disk and clobbered the mutation mid-eval. Every such mutation silently survived. The feature-loaded marker now runs immediately before `@source_evaluator.call`, so the in-progress eval is the canonical source any concurrent require sees. Without this, fork workers started from the same pre-`require` snapshot and the whole file scored 0% (EV-ekax, PR #1272, GH #1269)

## [0.30.4] - 2026-05-16

### Fixed

- **Minitest integration no longer errors every mutation when the project test helper calls `Minitest::Reporters.use!`** — a regression shipped in 0.30.3. The EV-5dxk zero-tests guard read `summary.count` from a `SummaryReporter` that evilution adds to its `CompositeReporter`. But when the target's test helper uses the `minitest-reporters` gem (`Minitest::Reporters.use!` — an extremely common setup), that plugin **replaces** the composite's reporters during `Minitest.init_plugins`, evicting evilution's own `SummaryReporter`. `summary.count` then never advanced — it read 0 even when tests ran — so the guard false-fired and every mutation was reported as errored ("no Minitest tests executed"), collapsing the score to a meaningless 0/0. `run_minitest` now derives the dispatched test-method count from the runnable registry (`Minitest::Runnable.runnables`), which is immune to reporter plugins. Surfaced by the EV-7764 pagy stability canary (EV-xfaj, PR #1260, GH #1259)
- **In-process isolation no longer false-kills genuinely-equivalent mutations and inflates the score** — `run_minitest` returned `passed: reporter.passed?`. When the target test helper calls `Minitest::Reporters.use!`, `init_plugins` replaces the composite's reporters with `minitest-reporters`' `DelegateReporter`, which delegates to a process-global reporter created once by `use!` and never reset between runs. Under in-process isolation one process runs every mutation in sequence, so that reporter's failures accumulate: `reporter.passed?` then reported `false` for every mutation after the first genuine kill, false-killing real survivors. On the pagy `request.rb` canary, in-process scored 98.44% against fork's correct 82.81%. `run_minitest` now attaches evilution's own fresh `SummaryReporter` to the composite **after** plugin init (so init_plugins cannot evict it) and reads the run's verdict from that per-run reporter; in-process and fork now converge (EV-wu8w, PR #1264, GH #1263)
- **`MinitestCrashDetector` survives reporter-plugin eviction** — the same `Minitest::Reporters.use!` swap that evicted evilution's `SummaryReporter` also detached the `MinitestCrashDetector`, which was attached to the composite before `initialize_minitest_state`. With the detector evicted, `build_minitest_result`'s `detector.only_crashes?` path went dead on `minitest-reporters` projects: a crash-only mutation result lost its `test_crashed` / `error` / `error_class` crash diagnostics and returned a plain killed result. The detector is now attached after plugin init alongside the `SummaryReporter`, keeping it in the live composite (EV-8z2n, PR #1265, GH #1262)

## [0.30.3] - 2026-05-16

### Fixed

- **Fork isolation no longer clobbers the eval'd mutation when the spec `require`s a lazily-loaded target file** — `MutationApplier` evals the mutated source straight into the VM, which does not register a `$LOADED_FEATURES` entry. When the project lazy-loads the target file (only the spec references it) and the spec then `require`s it, `require` found nothing loaded and re-read the **original** file from disk, clobbering the mutation before any test ran. Every mutation then silently survived. In-process runs masked it — the first mutation's spec-load populated `$LOADED_FEATURES` for the rest of the process — but under fork isolation each worker restarts from the same pre-`require` snapshot, so the whole file scored 0%. `MutationApplier` now registers the mutated file's canonical (`File.realpath`) path in `$LOADED_FEATURES` after applying the mutation, so a later `require`/`require_relative` is a no-op. Surfaced by the EV-7764 pagy stability canary: `gem/lib/pagy/classes/request.rb` went from 0% to 82.8% under `--jobs 4` (EV-vxgl, PR #1256, GH #1253)
- **Minitest integration reports `:error` instead of a misleading 0% when zero test methods run** — if the dispatched Minitest run executed no test methods (the resolved spec registered no `Minitest::Runnable` suite — commonly because the project's tests use a different framework such as the `test-unit` gem, or `--spec` points at the wrong file), `reporter.passed?` returned `true` for the empty run and every mutation was scored *survived*, producing a meaningless 0%. `run_minitest` now reports the dispatched test-method count; a zero-count run yields an error-shaped result so `classify_status` maps it to `:error` and the high-error-rate warning fires, instead of silently inflating the denominator. The Minitest analogue of the EV-720r RSpec fix. Surfaced by the EV-9cd2 kaminari stability canary (kaminari runs on `test-unit`, not Minitest) (EV-5dxk, PR #1257, GH #1254)

## [0.30.2] - 2026-05-15

### Fixed

- **`method_body_replacement` no longer corrupts methods with a method-level `rescue`/`ensure`** — for the shorthand form `def foo; stmts; rescue => e; ...; end` (no explicit `begin`), Prism makes `DefNode#body` a `BeginNode` whose `location` spans the *entire* `def...end` block — the `def` keyword and matching `end` included. The operator replaced that whole range with `nil` / `self` / `super`, obliterating the method framing and leaving the replacement dangling at the enclosing class/module scope; `super` replacements then raised `NoMethodError: super called outside of method` at load time, and the run miscounted every such mutation as an error. The operator now targets only the leading statements (`body.statements`) when the body is a `BeginNode`, preserving the `rescue`/`else`/`ensure` clauses and the `def` framing; methods with a rescue/ensure-only body (no leading statements) emit no mutation. Super *detection* still scans the full body, so a `super` call in any clause keeps the bare-super replacement candidate. Surfaced by the EV-5rtm redis-rb stability canary — 5 methods in `lib/redis/client.rb` (`ensure_connected`, `call_v`, `blocking_call_v`, `pipelined`, `multi`) all-errored before this fix (EV-9a6c, PR #1251, GH #1247)
- **`Minitest.autorun` stub now runs before the user `--preload` file** — the EV-7u9c fix (0.30.1) stubbed `Minitest.autorun` from `Integration::Minitest#ensure_framework_loaded` and `run_baseline_test_file`, both of which execute *after* `Runner#perform_preload`. When the user passed `--preload <file>` and that file required `minitest/autorun` (typical for `spec_helper.rb` / `test_helper.rb`), the `at_exit` handler was installed during preload — before the stub took effect — and the misleading "invalid option: --integration" banner returned at process exit. `Evilution::Runner::IsolationResolver#perform_preload` now invokes `Evilution::Integration::Minitest.stub_autorun!` immediately before requiring the preload file when `config.integration == :minitest`; it is a no-op for the RSpec integration. Surfaced by the EV-xqv3 rouge stability canary, whose `spec/spec_helper.rb` requires `minitest/autorun` (EV-5nxs, PR #1249, GH #1248)

## [0.30.1] - 2026-05-15

### Fixed

- **Minitest 5.11+ / 6.x reporter contract: `MinitestCrashDetector` now implements `prerecord(klass, name)`** — `Minitest::AbstractReporter` calls `prerecord` on every reporter immediately before each test runs; the crash detector implemented `start` / `report` / `record` / `passed?` but not `prerecord`, so on any project using Minitest ≥ 5.11 every mutation aborted with `undefined method 'prerecord' for an instance of Evilution::Integration::MinitestCrashDetector` and the run reported score 0.0 / all-errored regardless of actual test behavior. PR #1207 (EV-l6gx) addressed the `run_all_suites` vs `__run` dispatch gap but did not audit the reporter interface; this patch closes the remaining hole. Surfaced by the EV-5rtm redis-rb stability canary against Minitest 6.0.6 (EV-ju3o, PR #1243, GH #1240)
- **`Minitest.autorun` no longer installs an at-exit handler when invoked by evilution-loaded user helpers** — Minitest-based projects (redis-rb, mail, others) routinely have `test/helper.rb` do `require "minitest/autorun"`, which installs an `at_exit` block calling `Minitest.run(ARGV)`. Evilution loads those helpers during baseline and per-mutation execution, so the handler ran at evilution's own process exit, saw the original `ARGV` (still carrying `--integration`, `--spec`, `--preload`, ...), and Minitest's option parser printed a misleading "invalid option: --integration" usage banner after the mutation summary. `Evilution::Integration::Minitest.stub_autorun!` is now invoked right after `require "minitest"` in both the orchestrator's baseline path (`run_baseline_test_file`) and the per-instance `ensure_framework_loaded`; it redefines `Minitest.autorun` to a no-op (idempotently, keyed on the redefined method's `source_location`) so subsequent `require "minitest/autorun"` calls in user code never register the handler. Cosmetic-only fix: mutation scoring and exit code were already correct (EV-7u9c, PR #1244, GH #1241)

## [0.30.0] - 2026-05-15

### Added

- **Two new mutation operators bring the default registry to 74** — `LastExpressionRemoval` strips a trailing literal (`true`/`false`/`nil`/integer/symbol) from a method body, targeting the idiomatic `def predicate?; side_effect; true; end` pattern where the explicit literal return value is the high-signal behavior under test (EV-74e3, PR #1236). `ArgumentMethodCallReplacement` drops a method call appearing in argument position (`fn(x.attr)` → `fn(x)`, also inside hash values, array elements, and keyword arguments), surfacing the common log-payload / structured-data substitution pattern under its own operator name instead of buried under `method_call_removal` (EV-m47s, PR #1237)
- **`MutationPlanner` now deduplicates byte-identical mutations across operators** — key is `(file_path, mutated_source)`; first-registered operator wins. Eliminates wasted compute and inflated denominators when multiple operators produce the same edit (e.g. `statement_deletion` + `last_expression_removal` both deleting a trailing literal). `DeadCode` equivalence heuristic widened to recognize `last_expression_removal` so unreachable trailing literals retain equivalent-classification regardless of which operator name survives dedup (PR #1236 and follow-up review)
- **`BodyCallNeutralizer`: strip non-idempotent class/module body calls before re-eval in fork workers** — DSL registries (`register_mixin`, plugin registration, etc.) raise on second invocation because they assume single-eval semantics. The parent's preload already executed them; re-running them in the child fork is wasted work that aborts the eval before the mutated method takes effect. The neutralizer walks the Prism tree, replaces non-allowlisted top-level call statements with `nil` byte-for-byte, and extends the replacement range to cover heredoc bodies and terminators. Lazy-load-aware: a `$LOADED_FEATURES` snapshot taken at parent preload-end gates neutralization on whether the target file was actually preloaded — first-load-in-child files (e.g. roda's `lib/roda/plugins/typecast_params.rb`) are left intact so subsequent statements depending on those DSL-defined methods do not cascade `NameError` (#1195, EV-70hd PR #1232)
- **Setup-warning subsystem surfaces silent mutation failures** — when ≥80% of mutations error with ≥80% of those errors sharing a single error class, the warning formatter emits a class-specific hint (`NameError` → preload pointer; `LoadError` → require path; etc.) telling the user the run's numbers are unreliable and where to look. Wired into the CLI text reporter; visible in MCP `evilution-mutate` output too (#1216, #1168)
- **`mutate` CLI alias for `run`** — `evilution mutate path/foo.rb` is now equivalent to `evilution run path/foo.rb`; matches the `gem` name users reach for first (#1172)
- **`--preload PATH` flag with explicit fallback + error surface** — supersedes implicit autoloading. Resolves the path with explicit error messages when the file is missing or unreadable; falls back to the inferred convention only when explicitly opted in. MCP option parser accepts boolean `false` to disable preload entirely (#1171)
- **Method splicing for live method redefinition (`Evilution::Mutator::Splice`)** — supports method-level swaps in workers that previously required full source re-eval. Plumbed alongside the existing source-evaluator strategy (#1194)
- **Fork-protocol length-prefixed payloads** — replaces the ad-hoc line-terminated protocol that could hang when payload contents contained newlines. Worker self-baseline script can now use multiple jobs safely; the previous skip list for fork-using files was removed (#1176, #1177, #1178)
- **MCP / session / config schema versioning** — MCP tool envelopes carry `Evilution::MCP::CONTRACT_VERSION` (currently `1`); session JSON files declare a `schema_version`; configuration files (`.evilution.yml`) validated against a versioned schema. Forward compatibility now follows a documented policy (#856, #857, #858)
- **`docs/versioning.md`** — explicit policy on what counts as the public contract, what triggers a major bump, and how deprecations work. Linked from the top of `CHANGELOG.md` and the `## Versioning` section of `README.md` (#864)
- **Dual-runtime harness scripts for self-mutation testing** — run evilution's own suite against mutated evilution code in a separate Ruby process, isolating bootstrap effects (#1175)

### Fixed

- **Mutation scoring no longer silently inflates kills when RSpec returns nonzero with zero examples loaded** — `Baseline` now accepts `test_files:` and honors `--spec` at the baseline phase (previously the `--spec` flag was only consulted at mutation time, so the misleading "No matching test found... Use --spec to specify the test file" warning fired even when the user *did* pass `--spec`). `Integration::RSpec#execute_run` captures `RSpec.world.example_count` after the run; if the status is nonzero and zero examples loaded, `ResultBuilder#from_run` returns an explicit error hash so `classify_status` reports `:error` instead of falling through to `:killed`. Without this, environments with `fail_if_no_examples = true`, autoload mismatches, or spec-file load failures would mark every mutation as killed regardless of whether any example ran (EV-720r, PR #1234)
- **`class X < Struct.new(...)` (or `Data.define`, dynamic `Class.new`) no longer crashes the eval with `TypeError: superclass mismatch`** — `RedefinitionRecovery` now handles `TypeError` for messages containing "superclass mismatch": strips the constants the source declares (same path as the existing `ArgumentError 'already defined'` recovery) and retries once. If the retry still raises, the mutation reports `:error` rather than being silently miscounted as survived. Unblocks sinatra's `lib/sinatra/base.rb` and similar Rack-middleware-style anonymous-parent class patterns (EV-lqpn, PR #1235)
- **Gem detector now disambiguates multiple gemspecs in a single root** — when a repository ships e.g. `dotenv.gemspec` alongside `dotenv-rails.gemspec`, the previous `Dir.glob.first` was filesystem-order-dependent and often picked the wrong companion gem, triggering `uninitialized constant Rails` at preload. New three-tier resolution: exact-entry match against the target's `lib/foo.rb` path, then first-lib-subdirectory match, then the shortest gemspec basename as the conventional "parent" gem (EV-b0ee, PR #1224)
- **Heredoc-body orphaning across mutation operators centralized in `Evilution::AST::HeredocSpan`** — operators whose byte edit straddles a `<<~MARKER` anchor (argument_removal, argument_nil_substitution, method_call_removal, statement_deletion, method_body_replacement, block_removal, conditional_branch, string_interpolation, etc.) previously emitted unparseable mutations whenever the kept range included the heredoc opener without its body/terminator. `Mutator::Base#add_mutation` now extends the byte range via a single shared visitor; when the replacement itself re-references a heredoc anchor, the mutation is skipped rather than emitted as broken bytes (EV-bjot, PR #1223)
- **`receiver_replacement` skips reserved-keyword method names** — replacing `obj.if` (where `if` is the method name spelled as a Ruby keyword) with bare `if` produced unparseable Ruby. The operator now strips writer-form `=` suffixes and bails out when the candidate is a Ruby reserved keyword (EV-xsg2, PR #1222)
- **`rescue_removal` removes the orphan `else` clause when stripping the sole `rescue`** — `begin; ...; rescue Foo; ...; else; ...; end` with the rescue clause removed previously left a dangling `else` without a matching `rescue`, which is invalid Ruby. The operator now visits `BeginNode` directly and computes structural clause boundaries, dropping orphan else atoms (EV-kws8, PR #1221)
- **`explicit_super` "remove all args" trims the dangling comma** — `super(a, b)` → `super()` was correctly handled; `super(a, b,)` → `super(,)` was not. The trailing-args boundary now walks block-start / rparen / args-end so the resulting `super` is always parseable (EV-05tp, PR #1230)
- **`positional-after-keyword` syntax error in argument removal** — eliminated cases where positional arg removal left a kwarg followed by a positional in the result, which Ruby rejects (#1202)
- **Interpolated-node string parts no longer crash mutators on non-string segments** — `visit_interpolated_symbol_node` / `visit_interpolated_regular_expression_node` / `visit_interpolated_x_string_node` now skip embedded StringNode parts instead of treating them as standalone string literals (EV-nmhi, #1201)
- **`block_param_removal` anonymous-forward safety check** — body uses of `&` / `*` / `**` previously crashed when the corresponding block-param was removed. The operator now scans the body for anonymous forwards before deciding to remove (EV-2cv1, #1200)
- **`string_literal` adjacent-string concatenation handled** — Ruby implicitly concatenates adjacent string literals at parse time; mutating one half could leave a syntactically wrong fragment. The operator now detects adjacent quoted literals via Prism's part-type predicates and `opening_loc`, and skips when the result would be unparseable (#1220)
- **`string_literal` backslash-continuation handling** — multi-line literals joined by trailing `\` survived mutation as half-statements; now correctly span the continuation range (#1196)
- **`BodyCallNeutralizer` heredoc handling preserves parseable output** — when a neutralized call carried a heredoc argument, the replacement-range collector now walks every variant of interpolated-string / x-string / interpolated-symbol / regex with a `heredoc?` predicate and extends the end offset to the heredoc terminator's line (#1208)
- **Minitest version compatibility (Minitest 6 removed `__run`)** — `Integration::Minitest` now dispatches to the correct runner method based on the installed Minitest version; integration spec updated to assert the dispatch contract without `NoMethodError` regressions (#1207)
- **Nil-replacement crash in parallel cleanup accessors** — pool teardown could call accessors on partially-initialized worker state; nil-guards added in the affected paths (#1174)
- **`indexable?` skips symbol/string keys** — the index-conversion operators no longer attempt receiver mutation on call sites whose argument is itself a symbol/string literal (the receiver is necessarily indexable in those cases; the mutation produced no new signal) (#1173)
- **Error rate warning formatter wired into text reporter** — high error rates now produce a visible single-line warning before the mutations breakdown (#1168)

### Changed

- **MCP `evilution-mutate` default verbosity tightened to fit agent token caps** — minimal verbosity reports only the high-signal slice (summary + survived); full verbosity audited for unresolved-diffs leaks. Error sampling at minimal verbosity (cap per error class) prevents deadlock when thousands of mutations fail with the same exception (#1169, #1170, EV-r1tt)

## [0.29.0] - 2026-05-06

### Changed

- **Internal codebase hygiene sweep — `Metrics/AbcSize` ceiling tightened from `25` → `17`** — every method exceeding the new threshold was refactored via pure extract-method (no behavior change). ~48 sites across `lib/evilution/{ast,cli,compare,config,disable_comment,integration,mcp,mutation,mutator,parallel,reporter,runner,session,spec_ast_cache}` plus supporting `scripts/` utilities. No public API, CLI flag, or output changes; mutation operators and report emission are bit-identical. The upper bound on per-method ABC is now strictly enforced repo-wide — only `lib/evilution/runner.rb` remains in `.rubocop_todo.yml` (#371, PR #1160 + per-file sub-PRs)
- **Tuple-return methods across the runner pipeline migrated to named `Data.define` value objects** — internal-only refactor introducing typed return shapes for `Runner::MutationExecutor#call` (→`ExecutionResult`), `Runner::MutationPlanner#call` (→`Plan` plus internal `GenerationResult` / `DisabledFilterResult` / `SigFilterResult` / `EquivalentFilterResult`), `Parallel::WorkQueue` outputs, `Cache#partition` (→`Partition`), `Config.normalize_limit` (→`LimitResult`), `Mutation::Slicer.collect_chain` (→`Chain`), `slice_affected_lines` (→`AffectedSlices`), `CLI::Parser::FilesAndRanges` (→`ParsedPaths`), and assorted CLI command helpers. Improves call-site readability without affecting external behavior (#948, PR #1094; #949, PR #1095; #950, PR #1096; #951, PR #1097; #952, PR #1098; #953, PR #1099; #954, PR #1100; #955, PR #1101; #956, PR #1102)

## [0.28.0] - 2026-05-03

### Added

- **Operator profiles: `default` (current 72-operator set) and `strict` (adds aggressive truthiness mutators)** — pre-merge audits can opt into a more sensitive operator mix. The `strict` profile registers `PredicateToNil`, which replaces every `x.predicate?` call with `nil` to surface tests that only assert truthiness rather than exact return values. Wired through CLI (`--profile=strict`, `--strict` shortcut), `.evilution.yml` (`profile: strict`), and a new `Evilution::Mutator::Registry.for_profile(:default | :strict)` factory. `default` is unchanged, so existing CI runs are not affected (#920, PR #926)
- **Multi-file batch invocation documented** — `evilution path/a.rb path/b.rb path/c.rb` runs every file in a single Runner invocation so the framework (Rails, Sorbet, etc.) and the `preload` chain load **once** in the parent process. With `--isolation=fork` (default for Rails projects under `auto`), every per-mutation fork branches off the warmed parent — materially faster than `for f in ...; do bundle exec evilution run "$f"; done`. README now has a "5a. Multi-file batch scan" workflow section and an end-to-end runner spec covers two positional file paths; session save/load preserves per-file paths in `survived[].file` (#922, PR #927)

### Fixed

- **`Compare::Normalizer` mis-classified Mutant payload lines whose mutated source started with `--` or `++` as unified-diff headers** — pre-existing bug in `extract_from_mutant_diff` that would, for example, drop a removed line `--flag` (emitted as `---flag` in the diff). The new `DiffExtractor::Mutant` requires a trailing space after `---`/`+++` to match a header, preserving real payload. Equivalent Evilution/Mutant mutations on such lines now hash identically and `compare` no longer reports false additions/removals (#917, PR #934)

### Changed

- **Internal `Evilution::Compare::Fingerprint` SOLID refactor** — module-function form replaced with a class taking injectable `(extractor:, normalizer:)` collaborators and a `#call(diff:, file_path:, line:)` interface. Diff parsing extracted into `Evilution::Compare::DiffExtractor::{Evilution,Mutant}` strategy classes (one per format, common duck-typed interface), enabling open/closed extension for future tools without touching the orchestrator. `Compare::Normalizer` constructs both fingerprints once and reuses them across records (#917, PR #934)
- **`Evilution::Mutation` migrated to value-object composition** — sources, slice, parse status now Data.define-backed value objects (#822, PR #907)
- **`Evilution::Result::MutationResult` encapsulates memory and error state in dedicated Data.define value objects** — `MemoryStats` and `ErrorInfo` instead of flat positional fields (#823, PR #907)
- **`Reporter::Suggestion` registry/templates and the RSpec/Minitest template builders unified** — single `build` entrypoint per format (#824, PR #908; #849, PR #905; #850, PR #904)
- **`Reporter::HTML` namespace inlined into `report.rb`** — separate `namespace.rb` removed, autoload pattern adopted for sub-templates (#826, PR #909)
- **`Compare::LineNormalizer` extracted into its own class** — whitespace collapse separated from fingerprint orchestration (#829, PR #832)
- **`Evilution::Config` attribute assignment migrated to a transformation map** — single source of truth for type coercion across simple attributes (#830)
- **`Runner` `require` chain consolidated** — sub-component loading now centralized; circular-require pitfalls in `MutationExecutor` resolved with `Module#autoload` for child strategy/neutralizer files (#831)
- **Process cleanup helpers extracted into `Evilution::ProcessCleanup`** — `safe_kill(sig, pid)` and `safe_wait(pid)` shared by `Baseline`, `Isolation::Fork`, and `WorkQueue::Worker`, replacing scattered inline `rescue` modifiers swallowing `Errno::ESRCH`/`ECHILD` (#838)
- **`ProgressStreamer` and `Loop` error handling tightened** — generic `StandardError` rescues replaced with specific `Errno::EPIPE`/`Errno::EBADF`/etc.; once-only warning suppression added so a flood of failures cannot drown stderr (#827, #840)
- **Crash detector predicate methods renamed** — `has_*?` → `*?` per Ruby/RSpec conventions (`have_X` matcher calls `has_X?`; the renamed methods are still picked up by `be_X` matchers used in specs) (#839)
- **Rubocop hygiene sweep across 6 sites** — `Style/RescueModifier`, `Lint/UnusedMethodArgument`, `Lint/SuppressedException` (3 instances), `Security/Eval`, and `Security/MarshalLoad` (3 instances) inline disable comments removed in favor of either narrowed code, explanatory rescue-body comments, or main-`.rubocop.yml` per-file Excludes documented with the underlying trust boundary (#832, #833, #834, #835, #836, #837)

### Documentation

- **README "Operator Profiles" subsection** — explains the `default` vs `strict` profiles, how to opt in (CLI, config, shortcut), and what `strict` adds today (#920, PR #926)
- **README "5a. Multi-file batch scan" workflow** — documents Rails-loads-once amortisation and qualifies the speed claim by isolation mode (`fork` vs `in_process`) (#922, PR #927)
- **`.evilution.yml` template gained a `profile:` block** — generated by `evilution init` (#920, PR #926)

## [0.27.0] - 2026-04-26

### Added

- **`prism` declared as a runtime dependency (`>= 1.5, < 2`)** — Rails 7.1 stacks pin `prism 0.19` (which lacks `IfNode#subsequent`), causing a `NoMethodError` on the first `if` evilution mutated. Bundler now refuses incompatible prism versions at install time instead of crashing at runtime (#876, PR #891)
- **`--[no-]incremental` CLI flag** — `--no-incremental` overrides `incremental: true` from the config file for one invocation (cold-cache debugging, CI escape hatch). Last flag wins when both forms are given (#878, PR #897)
- **`--quiet-children` and `--quiet-children-dir DIR` flags** — redirect each forked worker's stdout/stderr to per-pid files under `tmp/evilution_children/<pid>.{out,err}` (configurable). Keeps parent output clean when app initializers (Datadog, Bullet, etc.) emit warnings on every fork. Trade-off: live worker errors only appear in the side files (`tail -f tmp/evilution_children/*.err`) (#880, PR #899)
- **Preload autodetect chain extended** — `Runner::IsolationResolver` now probes `spec/rails_helper.rb` → `spec/spec_helper.rb` → `test/test_helper.rb` (was: rails_helper + test_helper only). Rails projects that consolidate everything into `spec/spec_helper.rb` no longer need an explicit `preload:` setting. When the chain finds nothing under a Rails project, raises a `ConfigError` listing every path tried and pointing at `--preload` / `--no-preload` (#879, PR #898)
- **`evilution version` prints the bundled `mcp` gem version** — second line shows `mcp gem X.Y.Z (server compatibility)`. Run inside the same bundle the MCP server uses to confirm what's loaded after a `bundle update` (#883, PR #894)
- **Public feedback channel exposed across CLI and MCP surfaces** — when a run hits friction (`errored`, `unparseable`, or `unresolved` buckets > 0; baseline failure; MCP error response), evilution surfaces a single GitHub Discussions URL so agents can suggest filing feedback. CLI text reports gain a one-line footer; the CLI error-exit path emits the same line on stderr (both suppressed by `--quiet`, `--format=json`, `--format=html`). MCP `evilution-mutate` responses embed `feedback_url` + `feedback_hint` on friction (and always on error payloads); the `minimal` verbosity contract is preserved (no extra keys). New MCP `evilution-info action=feedback` returns `{ discussion_url, version, guidance_for_agent }` on demand for any feedback intent including missing-capability requests on clean runs. Tool descriptions and the README MCP "Feedback channel" subsection prominently document the **explicit user-consent gate** (agents must never post on the user's behalf without explicit approval) and **privacy expectations** (never include secrets, env vars, project name, file paths, source code, or class/method names from user code — the channel is public). By construction, no run-derived data is embedded in any feedback field — agent + user compose any actual payload themselves (#900, PR #901)

### Fixed

- **`Cache#store` crashed with `TypeError: no implicit conversion of nil into String` when `incremental: true` and `jobs >= 2`** — `Strategy::Parallel#run_batch` called `batch.each(&:strip_sources!)` before `@cache.store`, leaving `mutation.original_source = nil` for `Digest::SHA256.hexdigest`. Reordered so store runs before strip; added a defensive nil-source guard in `Cache#store` mirroring the existing one in `Cache#fetch` (#875, PR #890)
- **`block_removal` produced unparseable mutations on block-pass arguments (`map!(&:sym)`, `index_by(&:id)`, `flat_map(&block)`)** — operator stripped the `BlockArgumentNode` from inside the call's parens, leaving a dangling open paren. Operator now skips emission when `node.block.is_a?(Prism::BlockArgumentNode)`; explicit `{}` / `do..end` blocks are unaffected (#881, PR #895)
- **`method_body_replacement` errored at runtime when generating the `super`-replacement on methods whose enclosing class had no parent implementation** — `super`-replacement now only emitted when the original body already calls `super` (`SuperNode` or `ForwardingSuperNode`), using that as a heuristic that a super target exists in this context. Methods without `super` get only the `nil` and `self` replacements (#877, PR #892)

### Documentation

- **README "Installing on Rails 7.1 + Ruby 3.3" section** — covers the `cgi 0.5.0` (Rails-pinned) vs `cgi 0.5.1` (Ruby 3.3 default-gem) Bundler activation conflict, the sidecar `Gemfile.local` workaround (`eval_gemfile("Gemfile")` + add evilution + prism), the `BUNDLE_GEMFILE=Gemfile.local` invocation, and guidance on whether to commit or `.gitignore` the resulting `Gemfile.local.lock` (#882, PR #893)
- **README MCP "After upgrading the gem: restart the MCP server" subsection** — explains that the MCP server is a long-lived stdio process the agent host spawns; `bundle update evilution` swaps the gem on disk but the running process keeps the old code in memory until restart. Symptom is opaque "Internal error" responses to flags the old build doesn't recognize (#883, PR #894)

## [0.26.0] - 2026-04-24

### Removed

- **Deprecated MCP session tools removed** — `evilution-session-list`, `evilution-session-show`, `evilution-session-diff` shims (deprecated since #637 after consolidation into `evilution-session`) deleted (#686, PR #851)

### Fixed

- **`preload` silently ignored under `:in_process` isolation** — `Runner::IsolationResolver#perform_preload` gated the preload on `resolve_isolation == :fork`, so non-Rails projects (auto-resolving to `:in_process`) silently skipped `preload:` from `.evilution.yml` or `--preload`. Preload now runs for `:in_process` too (#868, PR #871)
- **`--target ClassName` silently narrowed to git-changed files** — when only a class/method target was given with no file scope, `Runner::SubjectPipeline#target_files` fell back to `Git::ChangedFiles`, producing a misleading `no method found matching 'X'` error when the class file was not in the working-tree diff. Target files now resolve from the configured source when a method/class target is given without explicit file scope (#869, PR #872)

### Changed

- **Internal `Evilution::Compare` refactor** — `lib/evilution/compare.rb` split into one class per file under `lib/evilution/compare/` (`Categorizer`, `Detector`, `Fingerprint`, `InvalidInput`, `Normalizer`, `Record`); `rubocop:disable Style/OneClassPerFile` removed (#825, PR #852)
- **Internal `Evilution::Integration::Base` refactor** — decomposed into focused collaborators under `Evilution::Integration::Loading::*` (`SyntaxValidator`, `SourceEvaluator`, `ConstantPinner`, `RedefinitionRecovery`, `ConcernStateCleaner`, `MutationApplier`) plus shared helpers `Evilution::AST::ConstantNames` and `Evilution::LoadPath::SubpathResolver`. `Integration::Base` now delegates mutation application to an injectable `MutationApplier`; no user-visible behavior change (#845, PR #873)

## [0.25.0] - 2026-04-21

### Added

- **`compare` command** — compare two saved mutation runs (JSON files, e.g. `.evilution/results/*.json`) and categorize each mutation into fixed / new / persistent / flaky / reintroduced buckets; supports `--against PATH --current PATH` flag binding or positional paths, emits `--format json` or `text`. Useful for CI gates that track regressions between runs (#746, #749, #750, #810, #811, #812, #813)
- **Per-mutation example targeting** — when a mutation is scoped to a specific method, the RSpec integration filters the resolved spec file to only the examples whose body text references symbols from the mutated method; typical workloads run a fraction of the file per mutation. New flags: `--no-example-targeting` disables the optimization, `--example-targeting-fallback MODE` picks between `full_file` (default) and `unresolved` when no example matches. Also adds `--spec-pattern GLOB` to restrict resolved spec candidates (#732, #800, #801, #802, #803, PR #816)
- **`:unparseable` mutation status** — mutations whose generated source fails to parse (e.g. dangling heredoc openers after `method_body_replacement`) are short-circuited before test execution and reported as a separate status, excluded from the score like `:unresolved`. Includes HTML, JSON, and text reporter support, MCP `info statuses` action, and a dedicated HTML "Unparseable" details section (#724, #725, #726, #728, #731)
- **`:neutral` details in HTML report** — surfaces mutations that were reclassified as neutral (infra errors, baseline-failed specs) in a dedicated HTML section so users can distinguish them from real kills (#758, #759)
- **Per-worker SQLite DB isolation** — `Parallel::WorkQueue` sets `ENV["TEST_ENV_NUMBER"]` per forked worker (`""` for worker 1, `"2"` for worker 2, …) following the [`parallel_tests`](https://github.com/grosser/parallel_tests) convention; Rails apps whose `config/database.yml` interpolates `TEST_ENV_NUMBER` now get one SQLite file per worker. When a parallel run is detected against a SQLite-backed `test:` section, evilution prints a one-time startup notice pointing to the README (#817, #819)
- **Infrastructure error neutralization** — results are reclassified as `:neutral` when the failure came from test infrastructure rather than the mutation itself. Two independent paths: (1) `:error` from `LoadError` / `NameError` whose first backtrace frame is `spec_helper.rb`, `rails_helper.rb`, or `spec/support/`; (2) `:killed` from a CrashDetector `test_crashed` whose sole crash class is in `INFRA_CRASH_CLASSES` (`ActiveRecord::StatementTimeout`, `ActiveRecord::Deadlocked`, `ActiveRecord::ConnectionTimeoutError`, `ActiveRecord::LockWaitTimeout`, `Timeout::Error`, `SQLite3::BusyException`). Keeps mutation scores clean under parallel DB contention and broken spec setup (#757, #814, #818)
- **Worker recycling** — `Parallel::WorkQueue` accepts `worker_max_items: N` to spawn a fresh worker after every N mutations; prevents unbounded RSS growth on long parallel runs. Defaults to no recycling. Works alongside `prefetch > 1` with bounded overshoot (#785)
- **`evil` executable** — short alias for `evilution` (handy with `alias be='bundle exec'` → `be evil run ...`) (#720)
- **`:unresolved` mutation status** — mutations whose source file has no resolvable spec/test are reported as `:unresolved` (coverage gap, not a failure) instead of erroring out; `--fallback-full-suite` still opts into running the whole suite (#718, #719)
- **MCP `info statuses` action** — returns a glossary of mutation result statuses (survived / killed / timeout / error / neutral / equivalent / unresolved / unparseable) with descriptions (#756)
- **RSpec evilution templates** — scaffold files helping users stand up evilution config and CI workflows faster (#488)
- **Peak-RSS regression spec** — benchmark fixture that asserts a 250-mutation workload stays under the documented peak-RSS budget; guards against memory regressions in isolation and pool code paths (#748)
- **Source AST caching** — caches parsed ASTs keyed by path + mtime, reducing re-parse cost when the same source file is referenced by multiple mutation plans in one run (#772, #803)
- **Survived-mutant unified diff output** — CLI and JSON surfacing of unified diffs alongside each survived entry (and in `util mutation`), matching the inline-patch format used by reviewers (#733, #735, #737, #741)

### Changed

- **Argument mutators refactored** — shared collaborators for position-style argument mutators (array/hash/call args); no user-visible behavior change (#734)
- **`MCP::Mutate` refactored** — split into focused collaborators; no user-visible behavior change (#489)
- **`ReportTrimmer` enhancements** — supports new statuses (`:unresolved`, `:unparseable`, `:neutral`) and keeps JSON/HTML output compact on big runs (#763)
- **Minitest assertion lookup refactored** — assertion values use indexed lookup instead of linear scans when matching integration mutators (perf win on large test suites) (#780)
- **`SourceSurgeon` parse status exposed** — carries a `parse_status` field through to `MutationResult` so the runner can short-circuit unparseable mutations cleanly (#724)
- **Original and mutated slices tracked on every mutation** — `Mutation` now carries both `original_slice` and `mutated_slice`, enabling accurate diff rendering without re-reading source files (#730)

### Fixed

- **`ThreadError: can't be called from trap context` in `TempDirTracker.cleanup_all`** — the signal handler installed by `Runner` called `FileUtils.rm_rf` under `Signal.trap`, which raises `ThreadError` for mutex operations executed from a trap context; now the cleanup path avoids the mutex when invoked from trap and falls back to direct enumeration with graceful `Errno::ENOENT` rescue (#793)
- **`Encoding::UndefinedConversionError` under Rails with `Encoding.default_internal = UTF-8`** — `Parallel::WorkQueue` pipes default to text mode and transcoded ASCII-8BIT Marshal payloads to UTF-8, failing on any high byte with no UTF-8 mapping; all pipe ends are now forced into `binmode` (#786, #788)
- **Zombie worker processes on mid-run errors** — when a worker exited unexpectedly or the map raised, `Parallel::WorkQueue` left children in a zombie state until the main process exited; now reaps child PIDs on every error path (#747)
- **Preload / spec_helper load errors** (continued from 0.22.x) — consolidated fallback logic so missing `rspec-core` surfaces a clear `ConfigError` rather than a bare `LoadError` in parallel runs (#742, #743, #745)

## [0.24.0] - 2026-04-14

### Added

- **`--fallback-full-suite` CLI flag** — when a mutation has no matching spec/test (spec resolver finds nothing), run the whole test suite instead of marking the mutation `:unresolved` and skipping; opt-in so the default remains fast (#697, PR #707)

### Fixed

- **`require_relative` in mutated files broken for sibling files** — the previous temp-dir copy strategy wrote the mutated source to a scratch directory where sibling source files did not exist, so any `require_relative "./sibling"` inside a mutated file failed to resolve; `Evilution::Integration::Base` now evaluates mutated source via `eval` with `__FILE__` set to the original path, so `require_relative` and `__dir__` resolve against the real source tree (#700, PR #708)

### Changed

- **Internal `Evilution::Reporter::HTML` refactor** — `lib/evilution/reporter/html.rb` (previously 410 lines) decomposed into section collaborators with one ERB template per section and CSS extracted to `lib/evilution/reporter/html/assets/style.css`; no output changes (#487, PR #712)
- **Internal `Evilution::Runner` refactor** — extracted `BaselineRunner`, `IsolationResolver`, `MutationPlanner`, `SubjectPipeline`, `Diagnostics`, `MutationExecutor`, and `ReportPublisher` collaborators; no user-visible behavior change (#486, PR #711)
- **Internal `Evilution::CLI::Parser` refactor** — decomposed into `CommandExtractor`, `FileArgs`, `OptionsBuilder`, and `StdinReader`; no user-visible behavior change (#703, PR #706)

## [0.23.0] - 2026-04-14

### Changed

- **Internal CLI refactoring** — `lib/evilution/cli.rb` was decomposed into smaller, focused units for readability and maintainability; no user-visible behavior change (#485, PR #704)

### Fixed

- **`session show` / `session diff` / `util mutation` diff output double-spaced between lines** — the text printers piped each diff line through `io.puts` even though `String#each_line` already yields a trailing newline, so every diff line was separated by a blank line; now `line.chomp` strips the trailing newline before `puts` re-adds it, rendering diffs with correct spacing (PR #704)
- **`subjects` summary printed "1 subjects, 1 mutations"** — the summary line always pluralized, producing grammatically incorrect output for single-element results; now pluralizes both nouns independently via a `pluralize` helper so single counts read "1 subject, 1 mutation" (PR #704)
- **`session show` crashed on permission errors and other `SystemCallError`s** — `Session::Store#load` can raise `Errno::EACCES` or other `SystemCallError`s (e.g. permission denied on `File.read`) which were not rescued, causing a hard crash instead of a clean exit 2; now wraps `SystemCallError` as `Evilution::Error` in `Commands::SessionShow` for parity with `Commands::SessionDiff` (PR #704)

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
