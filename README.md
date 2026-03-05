# Evilution — Mutation Testing for Ruby

> **Purpose**: Validate test suite quality by injecting small code changes (mutations) and checking whether tests detect them. Surviving mutations indicate gaps in test coverage.

**License**: MIT (free, no commercial restrictions)
**Language**: Ruby >= 3.3
**Parser**: Prism (Ruby's official AST parser, ships with Ruby 3.3+)
**Test framework**: RSpec (currently the only supported integration)

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

### Commands

| Command   | Description                              | Default |
|-----------|------------------------------------------|---------|
| `run`     | Execute mutation testing against files   | Yes     |
| `init`    | Generate `.evilution.yml` config file    |         |
| `version` | Print version string                     |         |

### Options (for `run` command)

| Flag                    | Type    | Default      | Description                                       |
|-------------------------|---------|--------------|---------------------------------------------------|
| `-j`, `--jobs N`        | Integer | CPU cores    | Parallel worker count. Use `1` for sequential.    |
| `-t`, `--timeout N`     | Integer | 10           | Per-mutation timeout in seconds.                   |
| `-f`, `--format FORMAT` | String  | `text`       | Output format: `text` or `json`.                  |
| `--diff BASE`           | String  | _(none)_     | Git ref. Only mutate methods whose definition line changed since BASE. |
| `--min-score FLOAT`     | Float   | 0.0          | Minimum mutation score (0.0–1.0) to pass.         |
| `--no-coverage`         | Boolean | false        | Reserved; currently has no effect.                |
| `-v`, `--verbose`       | Boolean | false        | Verbose output.                                    |
| `-q`, `--quiet`         | Boolean | false        | Suppress output.                                   |

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
# jobs: 4            # parallel workers
# timeout: 10        # seconds per mutation
# format: text       # text | json
# min_score: 0.0     # 0.0–1.0
# integration: rspec # test framework
# coverage: true     # coverage-based test selection
```

**Precedence**: CLI flags override `.evilution.yml` values.

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
    "score": "float      — killed / (total - errors), range 0.0-1.0, rounded to 4 decimals",
    "duration": "float   — total wall-clock seconds, rounded to 4 decimals"
  },
  "survived": [
    {
      "operator": "string — mutation operator name (see Operators table)",
      "file": "string    — relative path to mutated file",
      "line": "integer   — line number of the mutation",
      "status": "string  — result status: 'survived', 'killed', 'timeout', or 'error'",
      "duration": "float — seconds this mutation took, rounded to 4 decimals",
      "diff": "string    — unified diff snippet",
      "suggestion": "string — actionable hint for surviving mutants (survived only)"
    }
  ],
  "killed": ["... same shape as survived entries ..."],
  "timed_out": ["... same shape as survived entries ..."],
  "errors": ["... same shape as survived entries ..."]
}
```

**Key metric**: `summary.score` — the mutation score. Higher is better. 1.0 means all mutations were caught.

## Mutation Operators (18 total)

Each operator name is stable and appears in JSON output under `survived[].operator`.

| Operator                  | What it does                              | Example                            |
|---------------------------|-------------------------------------------|------------------------------------|
| `arithmetic_replacement`  | Swap arithmetic operators                 | `a + b` -> `a - b`                |
| `comparison_replacement`  | Swap comparison operators                 | `a >= b` -> `a > b`               |
| `boolean_operator_replacement` | Swap `&&` / `\|\|`                   | `a && b` -> `a \|\| b`            |
| `boolean_literal_replacement`  | Flip boolean literals                 | `true` -> `false`                  |
| `nil_replacement`         | Replace expression with `nil`             | `expr` -> `nil`                    |
| `integer_literal`         | Boundary-value integer mutations          | `n` -> `0`, `1`, `n+1`, `n-1`     |
| `float_literal`           | Boundary-value float mutations            | `f` -> `0.0`, `1.0`               |
| `string_literal`          | Empty the string                          | `"str"` -> `""`                    |
| `array_literal`           | Empty the array                           | `[a, b]` -> `[]`                   |
| `hash_literal`            | Empty the hash                            | `{k: v}` -> `{}`                  |
| `symbol_literal`          | Replace with sentinel symbol              | `:foo` -> `:__evilution_mutated__` |
| `conditional_negation`    | Replace condition with `true`/`false`     | `if cond` -> `if true`            |
| `conditional_branch`      | Remove if/else branch                     | Deletes branch body                |
| `statement_deletion`      | Remove statements from method bodies      | Deletes a statement                |
| `method_body_replacement` | Replace entire method body with `nil`     | Method body -> `nil`               |
| `negation_insertion`      | Negate predicate methods                  | `x.empty?` -> `!x.empty?`         |
| `return_value_removal`    | Strip return values                       | `return x` -> `return`            |
| `collection_replacement`  | Swap collection methods                   | `map` -> `each`, `select` <-> `reject` |

## Recommended Workflows for AI Agents

### 1. Full project scan

```bash
bundle exec evilution run lib/ --format json --jobs 4 --min-score 0.8
```

Parse JSON output. Exit code 0 = pass, 1 = surviving mutants to address.

### 2. PR / diff-only scan (fast feedback)

```bash
bundle exec evilution run lib/ --format json --diff main --min-score 0.9
```

Mutates methods whose definition (starting) line is changed compared to `main` (the diff filter is based on the method’s first line, not any line in its body). Use this for incremental checks — it's fast and focused on newly added or moved methods and changed signatures.

### 3. Single-file targeted scan

```bash
bundle exec evilution run lib/specific_file.rb --format json
```

Use when you know which file was modified and want to verify its test coverage.

### 4. Fixing surviving mutants

For each entry in `survived[]`:
1. Read `file` at `line` to understand the code context
2. Read `operator` to understand what was changed
3. Read `suggestion` for a hint on what test to write
4. Write a test that would fail if the mutation were applied
5. Re-run evilution on just that file to verify the mutant is now killed

### 5. CI gate

```bash
bundle exec evilution run lib/ --format json --min-score 0.8 --quiet
# Exit code 0 = pass, 1 = fail, 2 = error
```

Note: `--quiet` suppresses all stdout output (including JSON). Use it in CI only when you care about the exit code and do not need JSON output.

## Internals (for context, not for direct use)

1. **Parse** — Prism parses Ruby files into ASTs with exact byte offsets
2. **Extract** — Methods are identified as mutation subjects
3. **Mutate** — Operators produce text replacements at precise byte offsets (source-level surgery, no AST unparsing)
4. **Isolate** — Each mutation runs in a `fork()`-ed child process (no test pollution)
5. **Test** — RSpec executes against the mutated source
6. **Report** — Results aggregated into text or JSON

## Repository

https://github.com/marinazzio/evilution
