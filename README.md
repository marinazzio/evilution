# Evilution

Free, MIT-licensed mutation testing for Ruby. Evilution validates your test suite quality by making small code changes (mutations) and checking whether your tests catch them.

Ruby is the only major language without a dominant free mutation testing tool. The existing `mutant` gem is commercially licensed. Evilution fills this gap as an MIT-licensed, AI-agent-first mutation testing engine using Prism (Ruby's official parser).

## Features

- **18 mutation operators** covering arithmetic, comparisons, booleans, literals, conditionals, and more
- **Source-level surgery** via Prism AST byte offsets — preserves formatting perfectly
- **Fork-based isolation** — each mutation runs in a child process, no test pollution
- **Parallel execution** — distribute mutations across multiple workers
- **Diff-based targeting** — only mutate code changed since a git ref
- **JSON + CLI output** — machine-readable for AI agents, human-readable for developers
- **Actionable suggestions** — tells you what test to write for each surviving mutant
- **Zero heavy dependencies** — Prism (ships with Ruby 3.3+), diff-lcs, OptionParser (stdlib)

## Installation

Add to your Gemfile:

```ruby
gem "evilution", group: :test
```

Then run:

```bash
bundle install
```

Or install directly:

```bash
gem install evilution
```

Requires Ruby >= 3.2.0.

## Quick Start

```bash
# Run against specific files
bundle exec evilution run lib/my_class.rb

# Run with JSON output (for CI/AI agents)
bundle exec evilution run lib/my_class.rb --format json

# Only mutate code changed since last commit
bundle exec evilution run lib/ --diff HEAD~1

# Parallel execution with 4 workers
bundle exec evilution run lib/ --jobs 4

# Set a minimum mutation score threshold
bundle exec evilution run lib/ --min-score 0.8
```

## CLI Usage

```
Usage: evilution [command] [options] [files...]

Commands:
  run       Run mutation testing (default)
  init      Generate a default .evilution.yml config file
  version   Print version

Options:
  -j, --jobs N           Number of parallel workers (default: CPU cores)
  -t, --timeout N        Per-mutation timeout in seconds (default: 10)
  -f, --format FORMAT    Output format: text, json (default: text)
      --diff BASE        Only mutate code changed since BASE ref
      --min-score FLOAT  Minimum mutation score to pass (0.0-1.0)
      --no-coverage      Disable coverage-based test selection
  -v, --verbose          Verbose output
  -q, --quiet            Suppress output
```

## Configuration

Generate a config file:

```bash
bundle exec evilution init
```

This creates `.evilution.yml`:

```yaml
# Evilution configuration
# jobs: 4
# timeout: 10
# format: text
# min_score: 0.0
# integration: rspec
# coverage: true
```

CLI flags override config file values.

## Output Formats

### Text (default)

```
Evilution v0.1.0 — Mutation Testing Results
============================================

Mutations: 42 total, 38 killed, 4 survived, 0 timed out
Score: 90.48% (38/42)
Duration: 12.34s

Survived mutations:
  comparison_replacement: lib/calculator.rb:15
    - a >= b
    + a > b

Result: PASS (score 90.48% >= 80.00%)
```

### JSON

```json
{
  "version": "0.1.0",
  "summary": {
    "total": 42,
    "killed": 38,
    "survived": 4,
    "score": 0.9048,
    "duration": 12.34
  },
  "survived": [
    {
      "operator": "comparison_replacement",
      "file": "lib/calculator.rb",
      "line": 15,
      "diff": "- a >= b\n+ a > b"
    }
  ]
}
```

## Mutation Operators

| # | Operator | Example |
|---|---|---|
| 1 | ArithmeticReplacement | `a + b` -> `a - b` |
| 2 | ComparisonReplacement | `a >= b` -> `a > b` |
| 3 | BooleanOperatorReplacement | `a && b` -> `a \|\| b` |
| 4 | BooleanLiteralReplacement | `true` -> `false` |
| 5 | NilReplacement | `expr` -> `nil` |
| 6 | IntegerLiteral | `n` -> `0`, `1`, `n+1`, `n-1` |
| 7 | FloatLiteral | `f` -> `0.0`, `1.0` |
| 8 | StringLiteral | `"str"` -> `""` |
| 9 | ArrayLiteral | `[a, b]` -> `[]` |
| 10 | HashLiteral | `{k: v}` -> `{}` |
| 11 | SymbolLiteral | `:foo` -> `:__evilution_mutated__` |
| 12 | ConditionalNegation | `if cond` -> `if true`/`if false` |
| 13 | ConditionalBranch | Remove if/else branch |
| 14 | StatementDeletion | Remove statements from method bodies |
| 15 | MethodBodyReplacement | Method body -> `nil` |
| 16 | NegationInsertion | `x.empty?` -> `!x.empty?` |
| 17 | ReturnValueRemoval | `return x` -> `return` |
| 18 | CollectionReplacement | `map` -> `each`, `select` <-> `reject` |

## How It Works

1. **Parse** — Prism parses target Ruby files into ASTs with exact byte offsets
2. **Extract** — Methods are extracted as mutation subjects
3. **Mutate** — Operators generate text replacements at precise byte offsets (source surgery)
4. **Isolate** — Each mutation runs in a forked child process
5. **Test** — RSpec runs against the mutated code
6. **Report** — Results aggregated and reported as JSON or human-readable text

## Exit Codes

| Code | Meaning |
|---|---|
| 0 | Mutation score meets threshold |
| 1 | Mutation score below threshold |
| 2 | Tool error (invalid config, parse failure, etc.) |

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/marinazzio/evilution.

1. Fork the repo
2. Create your feature branch (`git checkout -b feature/my-feature`)
3. Write tests for your changes
4. Run `bundle exec rspec` to verify
5. Commit and push
6. Open a Pull Request

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
