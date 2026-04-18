[![Gem Version](https://badge.fury.io/rb/evilution.svg)](https://badge.fury.io/rb/evilution)

# Evilution — Mutation Testing for Ruby

> **Purpose**: Validate test suite quality by injecting small code changes (mutations) and checking whether tests detect them. Surviving mutations indicate gaps in test coverage.

* **License**: MIT (free, no commercial restrictions)
* **Language**: Ruby >= 3.3
* **Parser**: Prism (Ruby's official AST parser, ships with Ruby 3.3+)
* **Test frameworks**: RSpec and Minitest

## Installation

Add to `Gemfile`:

```ruby
gem "evilution", group: :test
```

Then: `bundle install`

Or standalone: `gem install evilution`

## Command Reference

```
evilution [command] [options] [files...]
```

The shorter alias `evil` ships alongside `evilution` and accepts identical arguments (handy with `alias be='bundle exec'` → `be evil run ...`).

### Commands

| Command              | Description                                        | Default |
|----------------------|----------------------------------------------------|---------|
| `run`                | Execute mutation testing against files              | Yes     |
| `init`               | Generate `.evilution.yml` config file               |         |
| `version`            | Print version string                                |         |
| `subjects [files]`   | List mutation subjects with locations and counts    |         |
| `tests list [files]` | List spec files mapped to source files              |         |
| `session list`       | List saved session results                          |         |
| `session show FILE`  | Display detailed session results                    |         |
| `session diff A B`   | Compare two sessions (fixed/new/persistent)         |         |
| `session gc --older-than D` | Garbage-collect sessions older than D (e.g. 30d) |         |
| `util mutation`      | Preview mutations for a file or inline code         |         |
| `environment show`   | Display runtime environment and settings            |         |

### Options (for `run` command)

| Flag                         | Type    | Default      | Description                                       |
|------------------------------|---------|--------------|---------------------------------------------------|
| `-t`, `--timeout N`          | Integer | 30           | Per-mutation timeout in seconds.                   |
| `-f`, `--format FORMAT`      | String  | `text`       | Output format: `text`, `json`, or `html`.         |
| `--target EXPR`              | String  | _(none)_     | Only mutate matching methods. Supports method name (`Foo::Bar#calculate`), class (`Foo`), namespace wildcards (`Foo::Bar*`), method-type selectors (`Foo#`, `Foo.`), descendants (`descendants:Foo`), and source globs (`source:lib/**/*.rb`). |
| `--min-score FLOAT`          | Float   | 0.0          | Minimum mutation score (0.0–1.0) to pass.         |
| `--spec FILES`               | Array   | _(none)_     | Spec files to run (comma-separated). Defaults to auto-detection via `SpecResolver`. |
| `--spec-dir DIR`             | String  | _(none)_     | Include all `*_spec.rb` files in DIR recursively. Composable with `--spec`. |
| `-j`, `--jobs N`             | Integer | 1            | Number of parallel workers. Uses demand-driven work distribution with pipe-based IPC. |
| `--no-baseline`              | Boolean | _(enabled)_  | Skip baseline test suite check. By default, a baseline run detects pre-existing failures and marks those mutations as `neutral`. |
| `--fail-fast [N]`            | Integer | _(none)_     | Stop after N surviving mutants (default 1 if no value given). |
| `-v`, `--verbose`            | Boolean | false        | Verbose output with RSS memory and GC stats per phase and per mutation; also prints error class, message, and first 5 backtrace lines for errored mutations. |
| `--suggest-tests`            | Boolean | false        | Generate concrete test code in suggestions (RSpec or Minitest, based on `--integration`). |
| `-q`, `--quiet`              | Boolean | false        | Suppress output.                                   |
| `--stdin`                    | Boolean | false        | Read target file paths from stdin (one per line).  |
| `--integration NAME`         | String  | `rspec`      | Test framework integration: `rspec` or `minitest`.  |
| `--incremental`              | Boolean | false        | Cache killed/timeout results; skip unchanged mutations on re-runs. |
| `--save-session`             | Boolean | false        | Persist results as timestamped JSON under `.evilution/results/`. |
| `--no-progress`              | Boolean | _(enabled)_  | Disable the TTY progress bar.                      |
| `--isolation MODE`           | String  | `auto`       | Isolation strategy: `auto`, `fork`, or `in_process`. `auto` selects `fork` for Rails projects. See [docs/isolation.md](docs/isolation.md). |
| `--preload FILE`             | String  | _(auto)_     | File to require in parent before forking workers (e.g. `spec/rails_helper.rb`). Auto-detected for Rails. |
| `--no-preload`               | Boolean | _(enabled)_  | Disable parent-process preload.                     |
| `--skip-heredoc-literals`    | Boolean | false        | Skip all string literal mutations inside heredocs.  |
| `--show-disabled`            | Boolean | false        | Report mutations skipped by `# evilution:disable` comments. |
| `--fallback-full-suite`      | Boolean | false        | When no matching spec/test resolves for a mutation, run the whole test suite instead of marking it `:unresolved` and skipping. |
| `--baseline-session PATH`    | String  | _(none)_     | Saved session file for HTML report comparison.     |
| `-e CODE`, `--eval CODE`     | String  | _(none)_     | Inline Ruby code for `util mutation` command.      |

### Exit Codes

| Code | Meaning                                       | Agent action                          |
|------|-----------------------------------------------|---------------------------------------|
| 0    | Mutation score meets or exceeds `--min-score` | Success. No action needed.            |
| 1    | Mutation score below `--min-score`            | Parse output, fix surviving mutants.  |
| 2    | Tool error (bad config, parse failure, etc.)  | Check stderr, fix invocation.         |

## Configuration

Generate default config: `bundle exec evilution init`

Creates `.evilution.yml`:

```yaml
# timeout: 30              # seconds per mutation
# format: text             # text | json | html
# min_score: 0.0           # 0.0–1.0
# integration: rspec       # test framework: rspec, minitest
# suggest_tests: false     # concrete test code in suggestions (matches integration)
# save_session: false      # persist results under .evilution/results/
# isolation: auto          # auto | fork | in_process (auto selects fork for Rails)
# preload: null            # path to preload before forking; false to disable; auto-detects for Rails
# skip_heredoc_literals: false  # skip string literal mutations inside heredocs (recommended for Rails: heredoc SQL/templates rarely have test coverage)
# show_disabled: false     # report mutations skipped by disable comments
# baseline_session: null   # path to session file for HTML comparison
# ignore_patterns: []      # AST patterns to exclude (see docs/ast_pattern_syntax.md)
# progress: true           # TTY progress bar
```

**Precedence**: CLI flags override `.evilution.yml` values.

## Disable Comments

Suppress mutations on specific code with inline comments:

```ruby
# Disable a single line
log(message) # evilution:disable

# Disable an entire method (place comment immediately before def)
# evilution:disable
def infrastructure_method
  # no mutations generated for this method body
end

# Disable a region
# evilution:disable
setup_logging
configure_metrics
# evilution:enable
```

Use `--show-disabled` to see which mutations were skipped.

## JSON Output Schema

Use `--format json` for machine-readable output. Schema:

```json
{
  "version": "string   — gem version",
  "timestamp": "string — ISO 8601 timestamp of the report",
  "summary": {
    "total": "integer    — total mutations generated",
    "killed": "integer   — mutations detected by tests (test failed = good)",
    "survived": "integer — mutations NOT detected (test passed = gap in coverage)",
    "timed_out": "integer — mutations that exceeded timeout",
    "errors": "integer   — mutations that caused unexpected errors",
    "neutral": "integer  — mutations whose tests already failed before mutation (baseline failure)",
    "equivalent": "integer — mutations proven to have identical behavior to the original",
    "unresolved": "integer — mutations where no spec file resolved (coverage gap, not a failure)",
    "score": "float      — killed / (total - errors - neutral - equivalent - unresolved), range 0.0-1.0, rounded to 4 decimals",
    "duration": "float   — total wall-clock seconds, rounded to 4 decimals",
    "peak_memory_mb": "float (optional) — peak RSS across all mutation child processes, in MB"
  },
  "survived": [
    {
      "operator": "string — mutation operator name (see Operators table)",
      "file": "string    — relative path to mutated file",
      "line": "integer   — line number of the mutation",
      "status": "string  — result status: 'survived', 'killed', 'timeout', 'error', 'neutral', 'equivalent', or 'unresolved'",
      "duration": "float — seconds this mutation took, rounded to 4 decimals",
      "diff": "string    — unified diff snippet",
      "suggestion": "string — actionable hint for surviving mutants (survived only)"
    }
  ],
  "coverage_gaps": [
    {
      "file": "string       — relative path to source file",
      "subject": "string    — method name (e.g. 'Foo#bar')",
      "line": "integer      — line number",
      "operators": ["string — operator names involved"],
      "count": "integer     — number of survived mutations in this gap",
      "mutations": ["... same shape as survived entries ..."]
    }
  ],
  "killed": ["... same shape as survived entries ..."],
  "neutral": ["... same shape as survived entries ..."],
  "equivalent": ["... same shape as survived entries ..."],
  "unresolved": ["... same shape as survived entries — coverage gap: no spec file resolved for these mutations"],
  "timed_out": ["... same shape as survived entries ..."],
  "errors": [
    {
      "... same shape as survived entries, plus: ...": "",
      "error_message": "string (optional) — error message from the failing mutation",
      "error_class":   "string (optional) — exception class name (e.g. 'SyntaxError', 'NoMethodError')",
      "error_backtrace": ["string (optional) — first 5 backtrace lines from the exception"]
    }
  ]
}
```

**Key metric**: `summary.score` — the mutation score. Higher is better. 1.0 means all mutations were caught.

### Mutation Statuses

| Status       | Meaning                                                               | Counted in score? |
|--------------|-----------------------------------------------------------------------|-------------------|
| `killed`     | A test failed when the mutation was applied — test suite caught it    | numerator + denominator |
| `survived`   | No test failed — gap in coverage                                       | denominator only  |
| `timeout`    | Test run exceeded `--timeout` — treated like survived for scoring     | denominator only  |
| `error`      | Mutation caused an unexpected error (syntax error, boot failure, etc.) | excluded from denominator |
| `neutral`    | Baseline tests already failed before mutation — not a meaningful signal | excluded          |
| `equivalent` | Mutation is provably identical to the original (e.g. no-op replacement) | excluded          |
| `unresolved` | No spec file resolved for the mutated source — **coverage gap, not a failure**. Use `--fallback-full-suite` to run the full suite instead. | excluded |

Unresolved mutations indicate a missing spec mapping — the file has no `_spec.rb` counterpart that the resolver could find. They are reported separately so you can act on them (add a spec, adjust spec naming, or opt in to the full-suite fallback) without inflating the error count.

## Mutation Operators (72 total)

Each operator name is stable and appears in JSON output under `survived[].operator`.

| Operator | What it does | Example |
|---|---|---|
| `arithmetic_replacement` | Swap arithmetic operators | `a + b` -> `a - b` |
| `comparison_replacement` | Swap comparison operators | `a >= b` -> `a > b` |
| `boolean_operator_replacement` | Swap `&&` / `\|\|` | `a && b` -> `a \|\| b` |
| `boolean_literal_replacement` | Flip boolean literals | `true` -> `false` |
| `nil_replacement` | Replace `nil` with `true`, `false`, `0`, `""` | `nil` -> `true` |
| `integer_literal` | Boundary-value integer mutations | `n` -> `0`, `1`, `n+1`, `n-1` |
| `float_literal` | Boundary-value float mutations | `f` -> `0.0`, `1.0` |
| `string_literal` | Empty the string | `"str"` -> `""` |
| `array_literal` | Empty the array | `[a, b]` -> `[]` |
| `hash_literal` | Empty the hash | `{k: v}` -> `{}` |
| `symbol_literal` | Replace with sentinel symbol | `:foo` -> `:__evilution_mutated__` |
| `conditional_negation` | Replace condition with `true`/`false` | `if cond` -> `if true` |
| `conditional_branch` | Remove if/else branch | Deletes branch body |
| `conditional_flip` | Flip `if` to `unless` and vice versa | `if cond` -> `unless cond` |
| `statement_deletion` | Remove statements from method bodies | Deletes a statement |
| `method_body_replacement` | Replace entire method body | Method body -> `nil`, `self`, `super` |
| `negation_insertion` | Negate predicate methods | `x.empty?` -> `!x.empty?` |
| `return_value_removal` | Strip return values | `return x` -> `return` |
| `collection_replacement` | Swap collection methods | `map` -> `each`, `select` <-> `reject` |
| `collection_return` | Replace collection return values | `return [1]` -> `return []` |
| `scalar_return` | Replace scalar return values | `return 42` -> `return 0` |
| `method_call_removal` | Remove method calls, keep receiver | `obj.foo(x)` -> `obj` |
| `argument_removal` | Remove individual arguments | `foo(a, b)` -> `foo(b)` |
| `argument_nil_substitution` | Replace arguments with `nil` | `foo(a, b)` -> `foo(nil, b)` |
| `keyword_argument` | Remove keyword defaults/params | `def foo(bar: 42)` -> `def foo(bar:)` |
| `multiple_assignment` | Remove targets or swap order | `a, b = 1, 2` -> `b, a = 1, 2` |
| `block_removal` | Remove blocks from method calls | `items.map { \|x\| x * 2 }` -> `items.map` |
| `block_pass_removal` | Remove block arguments passed with `&` | `items.map(&:to_s)` -> `items.map` |
| `range_replacement` | Swap inclusive/exclusive ranges | `1..10` -> `1...10` |
| `regexp_mutation` | Replace regexp with always/never matching | `/pat/` -> `/a\A/` |
| `regex_simplification` | Simplify regex quantifiers, anchors, ranges | `/\d+/` -> `/\d/`, `/[a-z]/` -> `/[az]/` |
| `receiver_replacement` | Drop explicit `self` receiver | `self.foo` -> `foo` |
| `send_mutation` | Swap semantically related methods | `detect` -> `find`, `map` -> `flat_map` |
| `compound_assignment` | Swap compound assignment operators | `+=` -> `-=`, `&&=` -> `\|\|=` |
| `local_variable_assignment` | Replace variable assignment with `nil` | `x = expr` -> `x = nil` |
| `instance_variable_write` | Replace ivar assignment with `nil` | `@x = expr` -> `@x = nil` |
| `class_variable_write` | Replace cvar assignment with `nil` | `@@x = expr` -> `@@x = nil` |
| `global_variable_write` | Replace gvar assignment with `nil` | `$x = expr` -> `$x = nil` |
| `mixin_removal` | Remove include/extend/prepend | `include Foo` -> removed |
| `superclass_removal` | Remove class inheritance | `class Foo < Bar` -> `class Foo` |
| `rescue_removal` | Remove rescue clauses | Deletes rescue block |
| `rescue_body_replacement` | Replace rescue body with `nil` | Rescue body -> `nil` |
| `inline_rescue` | Remove inline rescue fallback | `expr rescue val` -> `expr` |
| `ensure_removal` | Remove ensure blocks | Deletes ensure block |
| `break_statement` | Remove break statements | `break` -> removed |
| `next_statement` | Remove next statements | `next` -> removed |
| `redo_statement` | Remove redo statements | `redo` -> removed |
| `bang_method` | Swap bang with non-bang methods | `sort!` -> `sort` |
| `bitwise_replacement` | Swap bitwise operators | `a & b` -> `a \| b` |
| `bitwise_complement` | Remove or swap `~` | `~x` -> `x`, `~x` -> `-x` |
| `zsuper_removal` | Replace implicit `super` with `nil` | `super` -> `nil` |
| `explicit_super_mutation` | Mutate explicit super arguments | `super(a, b)` -> `super` |
| `index_to_at` | Replace `[]` with `.at()` for arrays | `arr[0]` -> `arr.at(0)` |
| `index_to_fetch` | Replace `[]` with `.fetch()` | `h[k]` -> `h.fetch(k)` |
| `index_to_dig` | Replace `[]` chains with `.dig()` | `h[a][b]` -> `h.dig(a, b)` |
| `index_assignment_removal` | Remove `[]=` assignments | `h[k] = v` -> removed |
| `pattern_matching_guard` | Remove/negate pattern guards | `in x if cond` -> `in x` |
| `pattern_matching_alternative` | Remove/reorder alternatives | `pat1 \| pat2` -> `pat1` |
| `pattern_matching_array` | Remove/wildcard array elements | `[a, b]` -> `[a, _]` |
| `yield_statement` | Remove yield or its arguments | `yield(x)` -> `yield` |
| `splat_operator` | Remove splat/double-splat | `foo(*args)` -> `foo(args)` |
| `defined_check` | Replace `defined?` with `true` | `defined?(x)` -> `true` |
| `regex_capture` | Swap or nil-ify capture refs | `$1` -> `$2`, `$1` -> `nil` |
| `loop_flip` | Swap while/until loops | `while cond` -> `until cond` |
| `string_interpolation` | Replace interpolation content with nil | `"hello #{name}"` -> `"hello #{nil}"` |
| `retry_removal` | Remove retry statements | `retry` -> `nil` |
| `case_when` | Remove/replace case/when branches | Remove `when` branch, body -> `nil`, remove `else` |
| `predicate_replacement` | Replace predicate calls with booleans | `x.empty?` -> `true`, `x.empty?` -> `false` |
| `equality_to_identity` | Replace equality with identity check | `a == b` -> `a.equal?(b)` |
| `lambda_body` | Replace lambda body with nil | `-> { expr }` -> `-> { nil }` |
| `begin_unwrap` | Remove begin/end wrapper | `begin; expr; end` -> `expr` |
| `block_param_removal` | Remove explicit block parameter | `def foo(&block)` -> `def foo` |

## MCP Server (AI Agent Integration)

Evilution includes a built-in [Model Context Protocol](https://modelcontextprotocol.io/) server for direct tool invocation by AI agents (Claude Code, VS Code Copilot, etc.).

### Setup

Create a `.mcp.json` file in your project root:

```json
{
  "mcpServers": {
    "evilution": {
      "type": "stdio",
      "command": "evilution",
      "args": ["mcp"],
      "env": {}
    }
  }
}
```

If using Bundler, set the command to `bundle` and args to `["exec", "evilution", "mcp"]`.

The server exposes the following tools:

| Tool | Description |
|---|---|
| `evilution-mutate` | Run mutation testing on target files with structured JSON results |
| `evilution-session` | Inspect mutation testing history — `action: list` browses saved sessions, `action: show` displays one, `action: diff` compares two (fixed/new/persistent survivors, score delta) |
| `evilution-info` | Discovery before mutation — `action: subjects` lists mutatable methods with mutation counts, `action: tests` resolves which specs cover given sources, `action: environment` dumps the effective config |

### Verbosity Control

The `evilution-mutate` tool accepts a `verbosity` parameter to control response size:

| Level       | Default | What's included                                              |
|-------------|---------|--------------------------------------------------------------|
| `summary`   | Yes     | `summary` + `survived` + `timed_out` + `errors`             |
| `full`      |         | All entries (killed/neutral/equivalent diffs stripped)        |
| `minimal`   |         | `summary` + `survived` only                                  |

Use `minimal` when context window budget is tight and you only need to see what survived. Use `full` when you need to inspect killed/neutral/equivalent entries for debugging.

### Enriched Survived Entries

Unlike `evilution --format json`, every survived entry returned by `evilution-mutate` carries extra fields so the agent can act without a second round-trip:

| Field | What it gives you |
|---|---|
| `subject` | `Class#method` for the mutated subject — points at the exact method to test |
| `spec_file` | Resolved spec/test path (when one exists) — e.g. an RSpec spec file or Minitest test file, so you can drop new tests straight into it |
| `next_step` | Concrete natural-language hint — "add a test in X that fails against this mutation at Y:line" |

These fields are added in addition to the existing `operator`, `file`, `line`, `diff`, `suggestion`, and `test_command` so agents can triage survivors in one pass.

### Concrete Test Suggestions

The `evilution-mutate` tool accepts a `suggest_tests` boolean parameter (default: `false`). When enabled, survived mutation suggestions contain concrete test code that an agent can drop into a test file, instead of static description text. It currently generates RSpec-style suggestions (`it`/`expect` blocks).

Pass `suggest_tests: true` in the `evilution-mutate` call to activate this mode. The CLI also supports `--suggest-tests`; when using the CLI, generated suggestions match the `--integration` setting (RSpec `it`/`expect` blocks or Minitest `def test_`/`assert_equal` methods).

### Project Config File

`evilution-mutate` and `evilution-info` load `.evilution.yml` (or `config/evilution.yml`) by default, matching `evilution` CLI behavior — so timeout, jobs, integration, target, ignore_patterns, and other project settings carry over without the agent having to re-pass them on every call. Explicit tool parameters still win over file settings.

Pass `skip_config: true` to ignore the project config file. This skips loading `.evilution.yml` / `config/evilution.yml`, but MCP-specific overrides (JSON output, quiet mode, preload disabled) and explicit tool parameters still apply.

### Iterative Workflow Parameters

`evilution-mutate` exposes the full set of CLI knobs agents need for iterative TDD:

| Parameter | Purpose |
|---|---|
| `incremental` | Cache killed/timeout results across runs — set `true` when iterating on the same files |
| `integration` | `rspec` or `minitest` |
| `isolation` | `auto`, `fork`, or `in_process` |
| `baseline` | `false` to skip the baseline suite check when you already know it's green |
| `save_session` | Persist results to `.evilution/results/` for inspection via `evilution-session` |

> **Note**: `.mcp.json` is gitignored by default since it is a local editor/agent configuration file.

## Recommended Workflows for AI Agents

### 1. Full project scan

```bash
bundle exec evilution run lib/ --format json --min-score 0.8
```

Parse JSON output. Exit code 0 = pass, 1 = surviving mutants to address.

### 2. PR / changed-lines scan (fast feedback)

```bash
bundle exec evilution run lib/foo.rb:15-30 lib/bar.rb:5-20 --format json --min-score 0.9
```

Target the exact lines you changed for fast, focused mutation testing. See line-range syntax below.

### 3. Line-range targeted scan (fastest)

```bash
bundle exec evilution run lib/foo.rb:15-30 --format json
```

Target exact lines you changed. Supports multiple syntaxes:

```bash
evilution run lib/foo.rb:15-30    # lines 15 through 30
evilution run lib/foo.rb:15       # single line 15
evilution run lib/foo.rb:15-      # from line 15 to end of file
evilution run lib/foo.rb          # whole file (existing behavior)
```

Methods whose body overlaps the requested range are included. Mix targeted and whole-file arguments freely:

```bash
evilution run lib/foo.rb:15-30 lib/bar.rb --format json
```

### 4. Method-name targeted scan

```bash
bundle exec evilution run lib/foo.rb --target Foo::Bar#calculate --format json
```

Target a specific method by its fully-qualified name. Useful when you want to focus on a single method without knowing its exact line numbers.

### 5. Single-file targeted scan

```bash
bundle exec evilution run lib/specific_file.rb --format json
```

Use when you know which file was modified and want to verify its test coverage.

### 6. Fixing surviving mutants

For each entry in `survived[]`:
1. Read `file` at `line` to understand the code context
2. Read `operator` to understand what was changed
3. Read `suggestion` for a hint on what test to write (use `--suggest-tests` for concrete test code)
4. Write a test that would fail if the mutation were applied
5. Re-run evilution on just that file to verify the mutant is now killed

### 7. Diagnosing errored mutations

Entries in the JSON `errors[]` array represent mutations that raised an exception (syntax error, load failure, or runtime crash) rather than producing a test outcome. Each entry includes `error_class`, `error_message`, and the first 5 `error_backtrace` lines. Use these fields to decide whether the error is a bug in the mutation operator (file an issue), a load-time problem in the mutated source (often `NoMethodError: super called outside of method` or constant-redefinition issues), or a genuine crash that the original tests should have caught. Run with `--verbose` to stream the same error details to stderr during the run.

### 8. CI gate

```bash
bundle exec evilution run lib/ --format json --min-score 0.8 --quiet
# Exit code 0 = pass, 1 = fail, 2 = error
```

Note: `--quiet` suppresses all stdout output (including JSON). Use it in CI only when you care about the exit code and do not need JSON output.

## Development

### Memory leak check

Run before releasing to verify no memory regressions:

```bash
bundle exec rake memory:check
```

Tests 4 paths (InProcess isolation, Fork isolation, mutation generation + stripping, parallel pool) by running repeated iterations and asserting RSS stays flat. Configurable via environment variables:

- `MEMORY_CHECK_ITERATIONS` — number of iterations per check (default: 50)
- `MEMORY_CHECK_MAX_GROWTH_KB` — maximum allowed RSS growth in KB (default: 10240 = 10 MB)

## Internals (for context, not for direct use)

1. **Parse** — Prism parses Ruby files into ASTs with exact byte offsets
2. **Extract** — Methods are identified as mutation subjects
3. **Filter** — Disable comments, Sorbet `sig` blocks, and AST ignore patterns exclude mutations before execution
4. **Mutate** — 72 operators produce text replacements at precise byte offsets (source-level surgery, no AST unparsing); heredoc literal text is skipped by default
5. **Isolate** — Mutations are applied to temporary file copies (never modifying originals); load-path redirection ensures `require` resolves the mutated copy. Default isolation is in-process for plain Ruby projects and fork for Rails projects (auto-detected); `--isolation fork` forces forked child processes. Both sequential and parallel (`--jobs N`) modes respect the configured isolation strategy
6. **Test** — The configured test framework (RSpec or Minitest) executes against the mutated source
7. **Collect** — Source strings and AST nodes are released after use to minimize memory retention
8. **Report** — Results aggregated into text, JSON, or HTML, including efficiency metrics and peak memory usage

## Repository

https://github.com/marinazzio/evilution
