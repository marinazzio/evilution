[![Gem Version](https://badge.fury.io/rb/evilution.svg)](https://badge.fury.io/rb/evilution)

# Evilution — Mutation Testing for Ruby

> **Purpose**: Validate test suite quality by injecting small code changes (mutations) and checking whether tests detect them. Surviving mutations indicate gaps in test coverage.

* **License**: MIT (free, no commercial restrictions)
* **Language**: Ruby >= 3.3
* **Parser**: Prism (Ruby's official AST parser, ships with Ruby 3.3+)
* **Test framework**: RSpec (currently the only supported integration)

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
| `-t`, `--timeout N`     | Integer | 10           | Per-mutation timeout in seconds.                   |
| `-f`, `--format FORMAT` | String  | `text`       | Output format: `text` or `json`.                  |
| `--target METHOD`       | String  | _(none)_     | Only mutate the named method (e.g. `Foo::Bar#calculate`). |
| `--min-score FLOAT`     | Float   | 0.0          | Minimum mutation score (0.0–1.0) to pass.         |
| `--spec FILES`          | Array   | _(none)_     | Spec files to run (comma-separated). Defaults to `spec/`. |
| `-j`, `--jobs N`        | Integer | 1            | Number of parallel workers. Pool forks per batch; mutations run in-process inside workers. |
| `--no-baseline`         | Boolean | _(enabled)_  | Skip baseline test suite check. By default, a baseline run detects pre-existing failures and marks those mutations as `neutral`. |
| `--fail-fast [N]`       | Integer | _(none)_     | Stop after N surviving mutants (default 1 if no value given). |
| `-v`, `--verbose`       | Boolean | false        | Verbose output with RSS memory and GC stats per phase and per mutation. |
| `--suggest-tests`       | Boolean | false        | Generate concrete RSpec test code in suggestions instead of static descriptions. |
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
# timeout: 10           # seconds per mutation
# format: text          # text | json
# min_score: 0.0        # 0.0–1.0
# integration: rspec    # test framework
# suggest_tests: false  # concrete RSpec test code in suggestions
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
    "duration": "float   — total wall-clock seconds, rounded to 4 decimals",
    "peak_memory_mb": "float (optional) — peak RSS across all mutation child processes, in MB"
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

The server exposes an `evilution-mutate` tool that accepts target files, method targets, spec overrides, parallelism, and timeout options — returning structured JSON results directly to the agent.

### Verbosity Control

The MCP tool accepts a `verbosity` parameter to control response size:

| Level       | Default | What's included                                              |
|-------------|---------|--------------------------------------------------------------|
| `summary`   | Yes     | `summary` + `survived` + `timed_out` + `errors`             |
| `full`      |         | All entries (killed/neutral/equivalent diffs stripped)        |
| `minimal`   |         | `summary` + `survived` only                                  |

Use `minimal` when context window budget is tight and you only need to see what survived. Use `full` when you need to inspect killed/neutral/equivalent entries for debugging.

### Concrete Test Suggestions

The MCP tool accepts a `suggest_tests` boolean parameter (default: `false`). When enabled, survived mutation suggestions contain concrete RSpec `it` blocks that an agent can drop into a spec file, instead of static description text.

Pass `suggest_tests: true` in the MCP tool call, or use `--suggest-tests` on the CLI, to activate this mode.

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
3. Read `suggestion` for a hint on what test to write (use `--suggest-tests` for concrete RSpec code)
4. Write a test that would fail if the mutation were applied
5. Re-run evilution on just that file to verify the mutant is now killed

### 7. CI gate

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
3. **Mutate** — Operators produce text replacements at precise byte offsets (source-level surgery, no AST unparsing)
4. **Isolate** — Default isolation is in-process; `--isolation fork` uses forked child processes. Parallel mode (`--jobs N`) always uses in-process isolation inside pool workers to avoid double forking
5. **Test** — RSpec executes against the mutated source
6. **Collect** — Source strings and AST nodes are released after use to minimize memory retention
7. **Report** — Results aggregated into text or JSON, including peak memory usage

## Repository

https://github.com/marinazzio/evilution
