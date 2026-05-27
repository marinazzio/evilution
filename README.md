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

Requires `prism >= 1.5, < 2`. Older Rails apps (e.g. Rails 7.1 pins `prism 0.19`) must upgrade prism — the gemspec constraint forces bundler to resolve a compatible 1.x version. If your app pins `prism 2.x`, bundler will reject the install until evilution widens its upper bound.

### Installing on Rails 7.1 + Ruby 3.3

Two Bundler conflicts hit fresh installs on this stack:

1. **`cgi` activation conflict.** Rails 7.1's `Gemfile.lock` pins `cgi 0.5.0`. Ruby 3.3.x ships `cgi 0.5.1` as a default gem. Loading evilution via Bundler aborts with:

   ```
   Gem::LoadError: can't activate cgi-0.5.1, already activated cgi-0.5.0.
   Make sure all dependencies are added to Gemfile.
   ```

2. **`prism` pin.** Same lockfile pins `prism 0.19`, which lacks the `IfNode#subsequent` accessor evilution uses (older Prism releases exposed it as `consequent`). Symptom: `NoMethodError: undefined method 'subsequent' for an instance of Prism::IfNode`.

Both resolve cleanly with a sidecar `Gemfile.local` that re-evaluates the project Gemfile and adds evilution + prism on top — no edits to the main `Gemfile.lock`:

```ruby
# Gemfile.local
eval_gemfile("Gemfile")

group :test, :development do
  gem "evilution"
  gem "prism", "~> 1.5"
end
```

Then invoke evilution against that Gemfile:

```sh
BUNDLE_GEMFILE=Gemfile.local bundle install
BUNDLE_GEMFILE=Gemfile.local bundle exec evilution run lib/foo.rb
```

The first command writes a sibling `Gemfile.local.lock`. Decide whether to commit or `.gitignore` it the same way you would for any developer-only Gemfile — typically gitignored when only one or two engineers run mutation testing locally, committed when CI also runs evilution against the sidecar Gemfile.

The evilution gemspec already declares `prism >= 1.5, < 2`, so adding the `gem "prism"` line above is only necessary on stacks that also pin prism in `Gemfile.lock`.

## Command Reference

```
evilution [command] [options] [files...]
```

The shorter alias `evil` ships alongside `evilution` and accepts identical arguments (handy with `alias be='bundle exec'` → `be evil run ...`).

Every command, subcommand, and flag listed in this section is part of evilution's public CLI contract; see [docs/versioning.md](docs/versioning.md) for stability and deprecation rules.

### Commands

| Command              | Description                                        | Default |
|----------------------|----------------------------------------------------|---------|
| `run` (alias `mutate`) | Execute mutation testing against files            | Yes     |
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
| `compare --against A --current B` | Compare two saved session JSON files into fixed / new / persistent / flaky / reintroduced buckets |         |

### Options (for `run` command)

| Flag                         | Type    | Default      | Description                                       |
|------------------------------|---------|--------------|---------------------------------------------------|
| `-t`, `--timeout N`          | Integer | 30           | Per-mutation timeout in seconds.                   |
| `-f`, `--format FORMAT`      | String  | `text`       | Output format: `text`, `json`, or `html`.         |
| `--target EXPR`              | String  | _(none)_     | Only mutate matching methods. Supports method name (`Foo::Bar#calculate`), class (`Foo`), namespace wildcards (`Foo::Bar*`), method-type selectors (`Foo#`, `Foo.`), descendants (`descendants:Foo`), and source globs (`source:lib/**/*.rb`). |
| `--min-score FLOAT`          | Float   | 0.0          | Minimum mutation score (0.0–1.0) to pass.         |
| `--spec FILES`               | Array   | _(none)_     | Spec files to run (comma-separated). Defaults to auto-detection via `SpecResolver`. |
| `--spec-dir DIR`             | String  | _(none)_     | Include all `*_spec.rb` files in DIR recursively. Composable with `--spec`. |
| `--spec-pattern GLOB`        | String  | _(none)_     | Restrict resolved spec candidates to files matching GLOB (e.g. `spec/models/**/*_spec.rb`). |
| `--no-example-targeting`     | Boolean | _(enabled)_  | Disable per-mutation example targeting (always run every example in the resolved spec file). Example targeting scans each example body for symbols from the mutated method and runs only the matching subset. |
| `--example-targeting-fallback MODE` | String | `full_file` | Behavior when no example matches: `full_file` (run the whole spec file) or `unresolved` (skip the mutation as `:unresolved`). |
| `-j`, `--jobs N`             | Integer | 1            | Number of parallel workers. Uses demand-driven work distribution with pipe-based IPC. |
| `--no-baseline`              | Boolean | _(enabled)_  | Skip baseline test suite check. By default, a baseline run detects pre-existing failures and marks those mutations as `neutral`. |
| `--[no-]canary`              | Boolean | _(enabled)_  | Run a proof-of-life synthetic mutation at session start; abort the run if the pipeline misreports it. Catches misconfigured isolation, broken autoload, and reporter-plugin eviction before any real score is produced. Pass `--no-canary` to skip (e.g. CI speed, or when the canary itself is the thing under test). |
| `--fail-fast [N]`            | Integer | _(none)_     | Stop after N surviving mutants (default 1 if no value given). |
| `-v`, `--verbose`            | Boolean | false        | Verbose output with RSS memory and GC stats per phase and per mutation; also prints error class, message, and first 5 backtrace lines for errored mutations. |
| `--suggest-tests`            | Boolean | false        | Generate concrete test code in suggestions (RSpec or Minitest, based on `--integration`). |
| `-q`, `--quiet`              | Boolean | false        | Suppress output.                                   |
| `--stdin`                    | Boolean | false        | Read target file paths from stdin (one per line).  |
| `--integration NAME`         | String  | `rspec`      | Test framework integration: `rspec` or `minitest`.  |
| `--[no-]incremental`         | Boolean | false        | Cache killed/timeout results; skip unchanged mutations on re-runs. Pass `--no-incremental` to override `incremental: true` from the config file for one invocation (e.g. cold-cache debugging). Last flag wins when both are given. |
| `--save-session`             | Boolean | false        | Persist results as timestamped JSON under `.evilution/results/`. |
| `--no-progress`              | Boolean | _(enabled)_  | Disable the TTY progress bar.                      |
| `--quiet-children`           | Boolean | false        | Redirect each forked worker's stdout/stderr to per-pid files under `tmp/evilution_children/<pid>.{out,err}` so noisy app initializers (Datadog, Bullet, etc.) don't merge with parent output. Trade-off: live worker errors only appear in the side files, not the terminal — `tail -f tmp/evilution_children/*.err` to watch them. |
| `--quiet-children-dir DIR`   | String  | `tmp/evilution_children` | Override the directory used by `--quiet-children`.    |
| `--isolation MODE`           | String  | `auto`       | Isolation strategy: `auto`, `fork`, or `in_process`. `auto` selects `fork` for Rails projects. See [docs/isolation.md](docs/isolation.md). |
| `--preload FILE`             | String  | _(auto)_     | File to require in parent before forking workers. Auto-detect chain for Rails projects: `spec/rails_helper.rb` → `spec/spec_helper.rb` → `test/test_helper.rb`. Errors with the full chain listed if none exist; pass `--no-preload` to opt out. |
| `--no-preload`               | Boolean | _(enabled)_  | Disable parent-process preload.                     |
| `--skip-heredoc-literals`    | Boolean | false        | Skip all string literal mutations inside heredocs.  |
| `--show-disabled`            | Boolean | false        | Report mutations skipped by `# evilution:disable` comments. |
| `--fallback-full-suite`      | Boolean | false        | When no matching spec/test resolves for a mutation, run the whole test suite instead of marking it `:unresolved` and skipping. |
| `--related-specs-heuristic`  | Boolean | false        | When a mutation removes an `includes(...)` call, also run matching specs from `spec/{requests,integration,features,system}` (Rails-style domain match on the source file's basename). Trades extra spec runs for higher kill rate on ORM mutations. |
| `--baseline-session PATH`    | String  | _(none)_     | Saved session file for HTML report comparison.     |
| `-e CODE`, `--eval CODE`     | String  | _(none)_     | Inline Ruby code for `util mutation` command.      |
| `--profile NAME`             | String  | `default`    | Operator profile: `default` or `strict`. `strict` adds aggressive truthiness mutators (e.g. replaces `x.predicate?` with `nil`) intended for pre-merge audits. |
| `--strict`                   | Boolean | false        | Shortcut for `--profile=strict`.                    |

### Options (for `session` subcommands)

| Flag                | Type    | Default              | Description                                                                                  |
|---------------------|---------|----------------------|----------------------------------------------------------------------------------------------|
| `--results-dir DIR` | String  | `.evilution/results` | Directory containing session result JSON files. Honored by `session list` and `session gc`.  |
| `--limit N`         | Integer | _(none)_             | (`session list`) Show only the N most recent sessions.                                       |
| `--since DATE`      | String  | _(none)_             | (`session list`) Show only sessions created on or after `DATE` (`YYYY-MM-DD`).               |
| `--older-than D`    | String  | _(required)_         | (`session gc`) Delete sessions older than `D` (e.g. `30d`, `24h`, `1w`).                     |

### Options (for `compare` command)

| Flag             | Type   | Default   | Description                                                                                          |
|------------------|--------|-----------|------------------------------------------------------------------------------------------------------|
| `--against PATH` | String | _(none)_  | Prior (older) session JSON to diff against. Positional first argument is accepted as a fallback.     |
| `--current PATH` | String | _(none)_  | Current (newer) session JSON. Positional second argument is accepted as a fallback.                  |

### Operator Profiles

Two profiles ship out of the box:

- **`default`** — the 74 stable operators registered in `Mutator::Registry.default`. Suitable for everyday CI runs; balances coverage signal against survivor noise.
- **`strict`** — adds extra truthiness mutators on top of `default`. Currently `PredicateToNil` (replaces every `x.predicate?` call with `nil` to surface tests that only assert truthiness rather than exact return values). Use for pre-merge audits where you want maximum sensitivity at the cost of more survivors.

Set via `--profile=strict`, the `--strict` shortcut, or `profile: strict` in `.evilution.yml`.

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
schema_version: 1            # opts into strict validation (rejects unknown keys, refuses future versions)
# timeout: 30              # seconds per mutation
# format: text             # text | json | html
# min_score: 0.0           # 0.0–1.0
# integration: rspec       # test framework: rspec, minitest
# suggest_tests: false     # concrete test code in suggestions (matches integration)
# save_session: false      # persist results under .evilution/results/
# isolation: auto          # auto | fork | in_process (auto selects fork for Rails)
# canary: true             # proof-of-life synthetic mutation at session start (false to skip)
# preload: null            # path to preload before forking; false to disable; auto-detects for Rails
# skip_heredoc_literals: false  # skip string literal mutations inside heredocs (recommended for Rails: heredoc SQL/templates rarely have test coverage)
# show_disabled: false     # report mutations skipped by disable comments
# baseline_session: null   # path to session file for HTML comparison
# ignore_patterns: []      # AST patterns to exclude (see docs/ast_pattern_syntax.md)
# progress: true           # TTY progress bar
# example_targeting: true  # per-mutation example targeting via body-token scan
# example_targeting_fallback: full_file  # full_file | unresolved
# spec_pattern: null       # restrict resolved spec candidates to files matching GLOB
```

**Precedence**: CLI flags override `.evilution.yml` values.

### Schema versioning

`.evilution.yml` may declare an integer `schema_version` (currently `1`). Behavior:

- **When declared** — strict mode. Unknown top-level keys raise `Evilution::ConfigError`. A `schema_version` greater than the installed gem supports is rejected so an old gem cannot silently misread a newer config.
- **When omitted** — legacy lenient mode. Unknown keys are ignored.

Compatibility policy for the `1.x` gem line:

- New configuration keys are added in MINOR releases (additive only). Each new key takes a default that preserves prior behavior.
- Existing keys are not removed, renamed, or have their semantics changed in any `1.x` release. Deprecated keys keep working through the entire `1.x` line; see [docs/versioning.md](docs/versioning.md).
- `schema_version` is bumped only on incompatible changes — i.e. only at the next MAJOR release. `schema_version: 2` will ship with `evilution 2.0`.

A JSON Schema covering every supported key lives at [`schema/evilution.config.schema.json`](schema/evilution.config.schema.json). Point editor / IDE YAML extensions at it for autocomplete and inline validation (e.g. VS Code `yaml.schemas`, JetBrains "Custom JSON Schema").

### Configuration reference

All keys recognised under `schema_version: 1`:

| Key                          | Type                          | Default                                | Description                                                                                                                              |
|------------------------------|-------------------------------|----------------------------------------|------------------------------------------------------------------------------------------------------------------------------------------|
| `schema_version`             | Integer                       | `1`                                    | Config schema version. Declaring it enables strict validation; omit for lenient mode.                                                    |
| `timeout`                    | Integer                       | `30`                                   | Per-mutation timeout in seconds.                                                                                                         |
| `format`                     | String                        | `text`                                 | Output format: `text`, `json`, `html`.                                                                                                   |
| `target`                     | String / null                 | `null`                                 | Filter expression: method (`Foo#bar`), class (`Foo`), namespace (`Foo*`), descendants (`descendants:Foo`), source glob (`source:**/*.rb`). |
| `min_score`                  | Float                         | `0.0`                                  | Minimum mutation score (0.0–1.0) for exit code 0.                                                                                        |
| `integration`                | String                        | `rspec`                                | Test framework: `rspec` or `minitest`.                                                                                                   |
| `verbose`                    | Boolean                       | `false`                                | Verbose output (RSS/GC stats per phase, error details for errored mutations).                                                            |
| `quiet`                      | Boolean                       | `false`                                | Suppress output.                                                                                                                         |
| `jobs`                       | Integer                       | `1`                                    | Number of parallel workers.                                                                                                              |
| `fail_fast`                  | Integer / null                | `null`                                 | Stop after N surviving mutants. `null` = disabled.                                                                                       |
| `baseline`                   | Boolean                       | `true`                                 | Run baseline test suite to detect pre-existing failures (marked `:neutral`).                                                             |
| `isolation`                  | String                        | `auto`                                 | Isolation strategy: `auto`, `fork`, `in_process`. `auto` selects `fork` for Rails projects.                                              |
| `incremental`                | Boolean                       | `false`                                | Cache killed/timeout results across runs.                                                                                                |
| `suggest_tests`              | Boolean                       | `false`                                | Generate concrete test code in survivor suggestions (matches `integration`).                                                             |
| `progress`                   | Boolean                       | `true`                                 | TTY progress bar.                                                                                                                        |
| `save_session`               | Boolean                       | `false`                                | Save session JSON under `.evilution/results/`.                                                                                           |
| `line_ranges`                | Hash                          | `{}`                                   | Per-file line-range constraints. Typically set via CLI; rare in YAML.                                                                    |
| `spec_files`                 | Array&lt;String&gt;           | `[]`                                   | Explicit spec files to run. Bypasses auto-detection when non-empty.                                                                      |
| `ignore_patterns`            | Array&lt;String&gt;           | `[]`                                   | AST patterns to skip during mutation generation. See [docs/ast_pattern_syntax.md](docs/ast_pattern_syntax.md).                           |
| `show_disabled`              | Boolean                       | `false`                                | Report mutations skipped by `# evilution:disable` comments.                                                                              |
| `baseline_session`           | String / null                 | `null`                                 | Saved session file path for HTML report comparison.                                                                                      |
| `skip_heredoc_literals`      | Boolean                       | `false`                                | Skip string literal mutations inside heredocs.                                                                                           |
| `related_specs_heuristic`    | Boolean                       | `false`                                | Append related request/integration/feature/system specs for `includes(...)` mutations.                                                   |
| `fallback_to_full_suite`     | Boolean                       | `false`                                | When no matching spec resolves, run the entire suite instead of marking the mutation `:unresolved`.                                      |
| `preload`                    | String / Boolean / null       | `null`                                 | File to preload in parent before forking. `false` to disable. `null` to auto-detect for Rails.                                           |
| `spec_mappings`              | Hash&lt;String, String/Array&gt; | `{}`                                | Custom mapping from source path to spec path(s).                                                                                         |
| `spec_pattern`               | String / null                 | `null`                                 | Glob restricting resolved spec candidates.                                                                                               |
| `example_targeting`          | Boolean                       | `true`                                 | Per-mutation example-level targeting.                                                                                                    |
| `example_targeting_fallback` | String                        | `full_file`                            | When targeting finds no example: `full_file` or `unresolved`.                                                                            |
| `example_targeting_cache`    | Hash                          | `{ max_files: 50, max_blocks: 10000 }` | LRU cache bounds for the example-targeting AST parser.                                                                                   |
| `quiet_children`             | Boolean                       | `false`                                | Redirect each worker's stdout/stderr to per-pid files under `quiet_children_dir`.                                                        |
| `quiet_children_dir`         | String                        | `tmp/evilution_children`               | Directory for `--quiet-children` per-pid log files.                                                                                      |
| `profile`                    | String                        | `default`                              | Operator profile: `default` or `strict`.                                                                                                 |
| `hooks`                      | Hash&lt;String, String&gt;    | `{}`                                   | Lifecycle hooks: event name → path to a Ruby file returning a `Proc`.                                                                    |

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

Use `--format json` for machine-readable output. The same shape is used for both stdout reports (`--format json`) and saved session files (`--save-session` → `.evilution/results/*.json`); session files add a small set of extra top-level fields described under [Session JSON files](#session-json-files) below.

Schema:

```json
{
  "schema_version": "integer — schema version of this JSON document (current: 1)",
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
    "unparseable": "integer — mutations whose mutated source did not parse (short-circuited, never executed)",
    "score": "float      — killed / (total - errors - neutral - equivalent - unresolved - unparseable), range 0.0-1.0, rounded to 4 decimals",
    "duration": "float   — total wall-clock seconds, rounded to 4 decimals",
    "peak_memory_mb": "float (optional) — peak RSS across all mutation child processes, in MB"
  },
  "survived": [
    {
      "operator": "string — mutation operator name (see Operators table)",
      "file": "string    — relative path to mutated file",
      "line": "integer   — line number of the mutation",
      "status": "string  — result status: 'survived', 'killed', 'timeout', 'error', 'neutral', 'equivalent', 'unresolved', or 'unparseable'",
      "duration": "float — seconds this mutation took, rounded to 4 decimals",
      "diff": "string    — legacy +/- diff snippet",
      "unified_diff": "string (optional, survived only) — git-style unified diff with `--- a/file`, `+++ b/file`, `@@` hunk header and sdiff body; omitted when source slices are unavailable",
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
  "unparseable": ["... same shape as survived entries — mutated source failed to parse and was never executed"],
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

### Session JSON files

Sessions saved by `--save-session` (under `.evilution/results/*.json`) and consumed by `evilution session show`, `evilution session diff`, `evilution compare`, and the HTML reporter share the schema above with these additions:

| Field                | Type    | Description                                                                                       |
|----------------------|---------|---------------------------------------------------------------------------------------------------|
| `git`                | Object  | `{ "sha": "<full SHA or null>", "branch": "<branch name or null>" }` captured at run time.        |
| `killed_count`       | Integer | Top-level convenience counter; mirrors `summary.killed`.                                          |
| `timed_out_count`    | Integer | Mirrors `summary.timed_out`.                                                                      |
| `error_count`        | Integer | Mirrors `summary.errors`.                                                                         |
| `neutral_count`      | Integer | Mirrors `summary.neutral`.                                                                        |
| `equivalent_count`   | Integer | Mirrors `summary.equivalent`.                                                                     |
| `skipped_count`      | Integer | Mutations skipped by `# evilution:disable` (omitted from `summary` unless positive).              |

Saved sessions also omit the per-status arrays (`killed`, `neutral`, `equivalent`, `unresolved`, `unparseable`, `timed_out`, `errors`) — only `survived` and `coverage_gaps` are persisted. The score, totals, and timestamps are stable for diff/compare consumers.

#### Schema versioning

Every session and stdout JSON document carries a top-level `schema_version` integer (currently `1`). On read:

- **`schema_version` matches what this gem supports** — proceed normally.
- **`schema_version` is omitted** — treated as version `1` (the JSON shape that defined version 1). Sessions written before this field existed continue to load.
- **`schema_version` is greater than what this gem supports** — `Evilution::Session::Store#load`, `evilution compare`, `evilution session show`, `evilution session diff`, and the HTML reporter raise `Evilution::Error` with the offending file path and a "Upgrade the evilution gem" message. We refuse to silently misread a newer document.

Compatibility policy for the `1.x` gem line:

- New top-level fields are added in MINOR releases (additive only). Consumers that ignore unknown fields keep working without changes.
- Existing fields are not removed, renamed, or have their semantics changed in any `1.x` release.
- `schema_version` is bumped only on incompatible changes — i.e. only at the next MAJOR release. `schema_version: 2` will ship with `evilution 2.0`. See [docs/versioning.md](docs/versioning.md) for the umbrella SemVer policy.

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
| `unparseable` | Mutated source failed to parse (e.g. dangling heredoc opener after `method_body_replacement`). Short-circuited — never executed. | excluded |

Unresolved mutations indicate a missing test mapping — the file has no corresponding test file that the resolver could find (for example, an RSpec `_spec.rb` file or a Minitest `_test.rb` file, depending on configuration). They are reported separately so you can act on them (add a test, adjust test naming, or opt in to the full-suite fallback) without inflating the error count.

## Mutation Operators (74 total)

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
| `last_expression_removal` | Strip trailing literal return from method body | `def foo?; warn; true; end` -> `def foo?; warn; end` |
| `argument_method_call_replacement` | Replace a method-call argument with its receiver | `fn(x.attr)` -> `fn(x)` |

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
| `evilution-info` | Discovery before mutation — `action: subjects` lists mutatable methods with mutation counts, `action: tests` resolves which specs cover given sources, `action: environment` dumps the effective config, `action: statuses` returns the mutation-result status glossary, `action: feedback` returns the public Discussions URL plus consent + privacy guidance for posting feedback |

### Verbosity Control

The `evilution-mutate` tool accepts a `verbosity` parameter to control response size:

| Level       | Default | What's included                                              |
|-------------|---------|--------------------------------------------------------------|
| `summary`   | Yes     | `summary` + `survived` + `timed_out` + `errors` + `unresolved` (non-survived entries shed `diff` and `error_backtrace` to bound payload size) |
| `full`      |         | All entries (killed/neutral/equivalent diffs stripped)        |
| `minimal`   |         | `summary` + `survived` (plus a trimmed sample of up to 3 errored entries when `errors > 0`) |

Use `minimal` when context window budget is tight and you only need to see what survived. The trimmed `errors` sample (each entry: `error_message`, `error_class`, location, plus the first 5 backtrace lines) is added so a partly-broken run is still self-diagnosable without escalating verbosity. Use `full` when you need to inspect killed/neutral/equivalent entries for debugging.

### Enriched Survived Entries

Unlike `evilution --format json`, every survived entry returned by `evilution-mutate` carries extra fields so the agent can act without a second round-trip:

| Field | What it gives you |
|---|---|
| `subject` | `Class#method` for the mutated subject — points at the exact method to test |
| `spec_file` | Resolved spec/test path (when one exists) — e.g. an RSpec spec file or Minitest test file, so you can drop new tests straight into it |
| `next_step` | Concrete natural-language hint — "add a test in X that fails against this mutation at Y:line" |

These fields are added in addition to the existing `operator`, `file`, `line`, `diff`, `unified_diff`, `suggestion`, and `test_command` so agents can triage survivors in one pass.

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

### After upgrading the gem: restart the MCP server

The MCP server is a long-lived stdio process spawned by the agent host. `bundle update evilution` swaps the gem on disk but the running process keeps the old code in memory — symptom is opaque "Internal error" responses to flags or shapes the old build doesn't recognize. Restart the server (reload the workspace in Claude Code / Copilot / etc.) so the new gem loads.

`evilution version` prints the gem version and the bundled `mcp` gem version on separate lines — run it in the same bundle the MCP server uses to confirm what's loaded.

### Feedback channel

When evilution causes friction (errors, usage problems, missing capabilities you wish were there), the MCP responses include a `feedback_url` plus `feedback_hint`. The `evilution-info` tool also exposes `action=feedback`, which returns the channel URL and posting guidance on demand.

**Agents must never post on the user's behalf without explicit user permission.** Show the user exactly what you would post, get explicit approval, then post. Never include secrets, environment variables, the project name, file paths, source code, or class/method names from user code — the feedback channel is public.

Discussion URL: <https://github.com/marinazzio/evilution/discussions>

### Contract stability

The three MCP tools (`evilution-mutate`, `evilution-session`, `evilution-info`) form evilution's public contract for AI agents. From `1.0.0` onwards the following are governed by the gem's [SemVer policy](docs/versioning.md):

- **Tool names**: `evilution-mutate`, `evilution-session`, `evilution-info`.
- **Input schemas**: every parameter listed in each tool's `input_schema` (name, type, enum values, `required`).
- **Action enumerations**: the action enum on `evilution-session` (`list`, `show`, `diff`) and `evilution-info` (`subjects`, `tests`, `environment`, `statuses`, `feedback`).
- **Output payload top-level shape**: the keys and value types documented per action below.
- **Error envelope**: an error response is a single text content with the response's `error` flag set to true. The body is a JSON object with at minimum an `error` key shaped `{ "type": <string>, "message": <string> }`; tools may add additional top-level keys (e.g. `evilution-mutate` includes `feedback_url` and `feedback_hint` to point agents at the public Discussions channel). Consumers must read the `error.type` discriminator and ignore unknown extras. The error type strings — currently `config_error`, `parse_error`, `not_found`, and `runtime_error` — are part of the contract; new types may be added in MINOR releases (additive).

#### Output `schema_version`

Successful MCP responses carry a top-level `schema_version` integer. Two distinct version spaces are in play; both happen to be `1` today and either may be bumped independently at the next MAJOR release:

- **MCP contract `schema_version`** — `Evilution::MCP::CONTRACT_VERSION` (currently `1`). Stamped on envelopes that exist solely to wrap MCP tool output: `evilution-info` action responses, `evilution-session list`, `evilution-session diff`. Bumped only when the MCP envelope shape itself changes incompatibly.
- **Session JSON `schema_version`** — `Evilution::Session::Schema::CURRENT_VERSION` (currently `1`). Embedded inside payloads whose shape is also written to disk and consumed elsewhere: `evilution-mutate` (returns a mutation report) and `evilution-session show` (returns a session JSON document). Bumped only when the report/session shape itself changes incompatibly.

Per-tool placement:

| Tool / action                  | `schema_version` source                  | Location in payload                                                                                  |
|--------------------------------|------------------------------------------|------------------------------------------------------------------------------------------------------|
| `evilution-mutate`             | `Session::Schema::CURRENT_VERSION`       | Top-level of the mutation report JSON (same shape as `--save-session` output).                      |
| `evilution-session` `list`     | `MCP::CONTRACT_VERSION`                  | Top-level of envelope: `{ "schema_version": 1, "sessions": [...] }`.                                 |
| `evilution-session` `show`     | `Session::Schema::CURRENT_VERSION`       | Inside the returned session JSON document.                                                           |
| `evilution-session` `diff`     | `MCP::CONTRACT_VERSION`                  | Top-level alongside `summary` / `fixed` / `new_survivors` / `persistent`.                            |
| `evilution-info` (all actions) | `MCP::CONTRACT_VERSION`                  | Top-level of every successful response, injected by the action response formatter.                   |

#### Per-tool output shapes

- **`evilution-mutate`** — full schema in the [JSON Output Schema](#json-output-schema) section. MCP-specific additions to each `survived` entry are documented in [Enriched Survived Entries](#enriched-survived-entries).
- **`evilution-session` `list`** — `{ "schema_version": Integer, "sessions": Array<{ file, timestamp, total, killed, survived, score, duration }> }`. Sessions are reverse-chronological; the array is filtered by `limit` when provided.
- **`evilution-session` `show`** — the parsed session JSON document, exactly as written under `.evilution/results/*.json`. Field reference: see [Session JSON files](#session-json-files).
- **`evilution-session` `diff`** — `{ "schema_version": Integer, "summary": { base_score, head_score, score_delta, base_survived, head_survived, base_total, head_total, base_killed, head_killed }, "fixed": Array, "new_survivors": Array, "persistent": Array }`. The mutation arrays carry the same per-mutation fields the session `survived` list uses (`operator`, `file`, `line`, `subject`, `diff`).
- **`evilution-info` `subjects`** — `{ "schema_version": Integer, "subjects": Array<{ name, file, line, mutations }>, "total_subjects": Integer, "total_mutations": Integer }`.
- **`evilution-info` `tests`** — `{ "schema_version": Integer, "specs": Array<{ source, spec }>, "unresolved": Array<String>, "total_sources": Integer, "total_specs": Integer }`.
- **`evilution-info` `environment`** — `{ "schema_version": Integer, "version": String, "ruby": String, "config_file": String|null, ... }` mirroring the effective `Evilution::Config`.
- **`evilution-info` `statuses`** — `{ "schema_version": Integer, "statuses": Array<{ name, meaning, in_score }> }`.
- **`evilution-info` `feedback`** — `{ "schema_version": Integer, "discussion_url": String, "consent": String, "privacy": String }`.

#### Deprecation cycle

When a parameter, action, or output field on the public MCP contract is deprecated:

1. The deprecation is announced in the CHANGELOG and the tool's `description` text gains a deprecation note.
2. The deprecated form remains functional for the entire `1.x` line — a deprecation introduced in `1.X` continues to work in every subsequent `1.X+N` release.
3. The earliest release that may remove the deprecated form is `2.0`. Removals are listed in the major-release migration guide.
4. Adding new parameters, new actions, or new top-level output fields is additive and ships in MINOR releases (existing consumers continue to work).

#### Not covered by the contract

- The exact wording of error `message` strings (the `type` is contract; the message is a hint that may be reworded).
- The exact ordering of arrays whose contract calls only for membership (e.g. `unresolved` source files).
- Progress-stream notification payloads sent through `server_context.notifications` — these are best-effort UI signals, not a stable API.
- Performance characteristics (request latency, memory, parallelism) — improvements ship in any release; regressions are bugs but not contract violations.
- Default values that are part of the gem's user-facing semantics (timeout, integration default, etc.) — these follow the umbrella SemVer policy and may be tuned.

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

### 5a. Multi-file batch scan

```bash
bundle exec evilution run lib/models/user.rb lib/models/account.rb lib/models/order.rb
```

Pass multiple file paths on a single invocation to amortise startup cost. The framework (Rails, Sorbet, etc.) and the `preload` chain (`spec/rails_helper.rb` → `spec/spec_helper.rb` → `test/test_helper.rb`) load **once** in the parent process. When `--isolation=fork` is selected (the default `--isolation=auto` resolves to `fork` on Rails projects), every subsequent mutation across all files forks from that warmed parent — materially faster than scripting a `for f in ...; do bundle exec evilution run "$f"; done` loop, which pays the bootstrap per file. With `--isolation=in_process` (default for non-Rails projects under `auto`), there is no per-mutation fork, but the parent-process boot still runs once instead of N times. Per-file paths and line numbers are preserved in the report (`survived[].file`, HTML grouping by source file).

### 6. Fixing surviving mutants

For each entry in `survived[]`:
1. Read `file` at `line` to understand the code context
2. Read `operator` to understand what was changed
3. Read `suggestion` for a hint on what test to write (use `--suggest-tests` for concrete test code)
4. Write a test that would fail if the mutation were applied
5. Re-run evilution on just that file to verify the mutant is now killed

### 7. Diagnosing errored mutations

Entries in the JSON `errors[]` array represent mutations that raised an exception (syntax error, load failure, or runtime crash) rather than producing a test outcome. Each entry includes `error_class`, `error_message`, and the first 5 `error_backtrace` lines. Use these fields to decide whether the error is a bug in the mutation operator (file an issue), a load-time problem in the mutated source (often `NoMethodError: super called outside of method` or constant-redefinition issues), or a genuine crash that the original tests should have caught. Run with `--verbose` to stream the same error details to stderr during the run.

### Long Minitest fork runs — not a hang

Minitest projects under `--isolation=fork` re-bootstrap the test environment (`test_helper.rb`, plugins, runnable state) once per mutation. On constant-heavy files (e.g. Shopify/liquid's `lib/liquid/lexer.rb`, ~270 mutations) the wall-clock cost is dominated by that per-fork bootstrap and any mutations that hit a `--timeout` rather than killing the test fast. A single-worker run (`-j 1`) on a few hundred mutations can take 4+ minutes; combined with `--no-progress` and a non-TTY stderr (CI, redirected logs) the run looks silent the entire time.

Recommended invocation for Minitest fork canaries:

```bash
RUBYOPT="-Itest" bundle exec evilution mutate lib/<file>.rb \
  -j 4 -t 10 \
  --integration=minitest --isolation=fork \
  --spec test/<dir>/<file>_test.rb
```

`-j 4` parallelises across workers, `-t 10` caps any mutation that pathologically loops at 10 s. Expect the run to print progress only when stderr is a TTY (use `bundle exec evilution mutate ... 2>&1 | tee log` to get progress while still saving output). The historical "Minitest fork hangs on liquid" report (EV-blnq / GH #1211) turned out to be a slow run + silent UX, not an actual deadlock — the worker logs show steady forward progress when captured via `--quiet-children --quiet-children-dir DIR`.

### 8. CI gate

```bash
bundle exec evilution run lib/ --format json --min-score 0.8 --quiet
# Exit code 0 = pass, 1 = fail, 2 = error
```

Note: `--quiet` suppresses all stdout output (including JSON). Use it in CI only when you care about the exit code and do not need JSON output.

### 9. Regression tracking across runs (`compare`)

```bash
bundle exec evilution run lib/ --format json --save-session
# later, after edits:
bundle exec evilution run lib/ --format json --save-session

bundle exec evilution compare \
  --against .evilution/results/<earlier>.json \
  --current  .evilution/results/<later>.json \
  --format json
```

Output buckets:

| Bucket          | Meaning |
|-----------------|---------|
| `fixed`         | Survived previously, killed now — the new test actually landed |
| `new`           | Did not exist previously, surviving now — a fresh gap |
| `persistent`    | Survived in both runs — carry-over debt |
| `reintroduced`  | Killed previously, survived now — regression |
| `flaky`         | Status flipped and back — unstable test |

Use in CI to gate merges on `reintroduced` being empty, or to surface `new` survivors for reviewer attention without failing the build on `persistent` debt.

## Parallel Runs with SQLite

Running with `-j N` forks worker processes. If your Rails app uses SQLite, every worker opens the same `db/test.sqlite3` file, and concurrent writers collide on the database-level lock. Symptoms: `ActiveRecord::StatementTimeout`, `SQLite3::BusyException`, and slow runs. Evilution classifies these crashes as `:neutral` (see [EV-toid / #814](https://github.com/taxdome/evilution/issues/814)) so the mutation score is not polluted, but the wall-clock penalty remains.

Evilution follows the [`parallel_tests`](https://github.com/grosser/parallel_tests) convention: each worker receives a `TEST_ENV_NUMBER` environment variable (`""` for worker 1, `"2"` for worker 2, `"3"` for worker 3, …). Interpolate it into `config/database.yml` so each worker gets its own SQLite file:

```yaml
test:
  adapter: sqlite3
  database: db/test<%= ENV['TEST_ENV_NUMBER'] %>.sqlite3
  pool: 5
  timeout: 5000
```

After the first `jobs > 1` run, each worker creates its own file (`db/test.sqlite3`, `db/test2.sqlite3`, …). Seed each with `rake db:test:prepare` before running Evilution, or ensure your preload sets up schema on connect.

When Evilution detects a parallel run against a SQLite-backed `config/database.yml`, it prints a one-time startup warning pointing to this section.

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
4. **Mutate** — 74 operators produce text replacements at precise byte offsets (source-level surgery, no AST unparsing); heredoc literal text is skipped by default. Identical byte-mutations from different operators are deduplicated by `(file_path, mutated_source)` so the count is not inflated by overlap
5. **Isolate** — Mutations are applied to temporary file copies (never modifying originals); load-path redirection ensures `require` resolves the mutated copy. Default isolation is in-process for plain Ruby projects and fork for Rails projects (auto-detected); `--isolation fork` forces forked child processes. Both sequential and parallel (`--jobs N`) modes respect the configured isolation strategy
6. **Test** — The configured test framework (RSpec or Minitest) executes against the mutated source
7. **Collect** — Source strings and AST nodes are released after use to minimize memory retention
8. **Report** — Results aggregated into text, JSON, or HTML, including efficiency metrics and peak memory usage

## Versioning

`evilution` follows [Semantic Versioning](https://semver.org). The full policy — what counts as the public contract, what triggers a major bump, how deprecations work — is documented in [docs/versioning.md](docs/versioning.md).

## Repository

https://github.com/marinazzio/evilution
