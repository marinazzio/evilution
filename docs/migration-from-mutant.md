# Migrating from `mutant` to Evilution

This guide is for teams moving off [`mutant`](https://github.com/mbj/mutant) — whose
runtime is under a commercial license — to Evilution, which is MIT-licensed with no
commercial restrictions. It maps the commands, config, and output you already know
onto their Evilution equivalents, and is honest about where the two tools differ.

Evilution is not a drop-in fork of mutant. It produces its own mutations with its own
operator set and selects work by **file path** rather than by subject expression. The
result is the same kind of signal — surviving mutations expose weak tests — but the
numbers and the workflow are not identical. The `compare` command (below) exists
precisely so you can line the two tools up and see the difference for yourself.

## TL;DR

| mutant | Evilution |
| --- | --- |
| `mutant run --use rspec -- 'MyApp::Foo*'` | `evilution run lib/my_app/ --target 'MyApp::Foo*'` |
| `mutant.yml` | `.evilution.yml` (run `evilution init` to scaffold) |
| `mutant-rspec` / `mutant-minitest` gems | built in: `--integration rspec\|minitest\|test-unit` |
| "mutation coverage" %, "alive" | "mutation score" 0.0–1.0, "survived" |
| commercial license for the runtime | MIT |

## 1. Install

Drop the mutant gems and add Evilution:

```ruby
# Gemfile — remove:  gem "mutant", "mutant-rspec"
gem "evilution", group: :test
```

```sh
bundle install
bundle exec evilution init   # writes a commented .evilution.yml
```

There is no separate integration gem to install — RSpec, Minitest, and Test::Unit
support ship in the core gem.

## 2. The core workflow shift: files, not subjects

mutant is **subject-driven**: you pass a match expression and it finds the code.
Evilution is **file-driven**: you pass file paths, and optionally narrow with
`--target`.

```sh
# mutant
bundle exec mutant run --use rspec -- 'MyApp::Calculator#add'

# evilution — point at the file, optionally filter to the method
bundle exec evilution run lib/my_app/calculator.rb --target 'MyApp::Calculator#add'

# whole directory, then filter by expression
bundle exec evilution run lib/ --target 'MyApp::Calculator*'
```

`--target` accepts the expression shapes you are used to, plus a source glob:

| Intent | mutant match | Evilution `--target` |
| --- | --- | --- |
| One method | `MyApp::Foo#bar` | `MyApp::Foo#bar` |
| One class | `MyApp::Foo` | `MyApp::Foo` |
| Namespace (recursive) | `MyApp::Foo*` | `MyApp::Foo*` |
| All instance methods | `MyApp::Foo#` | `MyApp::Foo#` |
| All singleton methods | `MyApp::Foo.` | `MyApp::Foo.` |
| Subclasses | _(n/a)_ | `descendants:MyApp::Foo` |
| By file glob | _(use file args)_ | `source:lib/**/*.rb` |

## 3. Command mapping

| Task | mutant | Evilution |
| --- | --- | --- |
| Run mutation testing | `mutant run -- 'Foo'` | `evilution run lib/foo.rb` (alias `mutate`; binary alias `evil`) |
| Choose framework | `--use rspec` / `mutant-minitest` | `--integration rspec\|minitest\|test-unit` |
| Parallel workers | `-j N` / `--jobs N` | `-j N` / `--jobs N` |
| Fail fast | `--fail-fast` | `--fail-fast [N]` (default 1) |
| Coverage gate | `--score` (default `1.0` / 100%) | `--min-score` (default `0.0`) |
| Preview mutations | `mutant util mutation` / `mutant environment subject list` | `evilution util mutation -e 'a + b'` / `evilution subjects lib/foo.rb` |
| Set load path / requires | `--include lib --require my_app` | handled by `--preload` (auto-detects `spec/spec_helper.rb` etc.) + Bundler |
| JSON report | session JSON (always written) | `--format json` (`--save-session` to persist) |
| Inline opt-out | `# mutant:disable` | `# evilution:disable` |
| Aggressive operators | _(always on)_ | `--profile strict` (or `--strict`) |

### Things mutant has that Evilution does not (yet)

- **`--since <git-ref>`** — mutant can restrict subjects to lines changed since a git
  ref. Evilution has no diff-aware selection. The closest tools are `--incremental`
  (caches `killed`/`timeout` results and skips unchanged mutations on re-runs — a
  different model) and `--target source:<glob>` / explicit file args to scope a run.

### Things Evilution adds

- `--format html` interactive report, and `evilution compare` (see §6).
- Per-mutation **example targeting** (runs only the examples that exercise the mutated
  code) — on by default, tune with `example_targeting*` keys.
- `--suggest-tests` emits concrete test code for survivors.
- Explicit `:unresolved` status when no spec maps to a source file (a coverage-gap
  signal rather than a silent skip).

## 4. Config translation (`mutant.yml` → `.evilution.yml`)

```yaml
# mutant.yml
integration:
  name: rspec
jobs: 8
includes:
  - lib
requires:
  - my_app
matcher:
  subjects:
    - MyApp::Billing*
  ignore:
    - MyApp::Billing::Legacy#deprecated
```

```yaml
# .evilution.yml
integration: rspec
jobs: 8
# `includes` / `requires` are usually unnecessary — Evilution preloads the test
# helper (and the gem entry) automatically. Override only if needed:
preload: spec/spec_helper.rb
# `matcher.subjects` -> run file args + --target; expression below is illustrative.
target: "MyApp::Billing*"
# `matcher.ignore` -> AST ignore patterns (see docs/ast_pattern_syntax.md) or an
# inline `# evilution:disable` comment on the method.
ignore_patterns: []
```

Key-by-key:

| `mutant.yml` | `.evilution.yml` | Notes |
| --- | --- | --- |
| `integration.name: rspec` | `integration: rspec` | string, not a mapping |
| `jobs` | `jobs` | same |
| `includes` | _(usually omit)_ | Bundler + `preload` cover the load path |
| `requires` | `preload` | a single preload file (autodetected by default) |
| `matcher.subjects` | `target` + file args | one expression; combine with positional paths |
| `matcher.ignore` | `ignore_patterns` / `# evilution:disable` | AST patterns or inline comments |
| `fail_fast` | `fail_fast` | integer N or `null` |
| `--score` gate (CLI; default `1.0`) | `min_score` | evilution defaults to `0.0` — set your own gate |
| _(n/a)_ | `profile: strict` | opt into aggressive truthiness mutators |

Run `evilution init` for a fully commented template, and point your editor at
`schema/evilution.config.schema.json` for autocomplete/validation.

## 5. Output differences

The vocabulary and the math differ — read this before comparing dashboards.

| Concept | mutant | Evilution |
| --- | --- | --- |
| Detected mutation | `killed` | `killed` |
| Undetected mutation | `alive` | `survived` |
| Headline metric | "mutation coverage" (%) | "mutation score" (0.0–1.0) |
| Pre-existing test failure | `neutral` / `noop` | `neutral` |
| Operator name in report | **not emitted** | emitted, e.g. `Arithmetic::Swap` |
| Per-mutation diff | unified diff with `@@` header + context | `- old` / `+ new` pair (and a full `unified_diff` for survivors) |
| Report shape | nested: session → subject → coverage results | flat per-status buckets |

**Score formula.** mutant's coverage is roughly `killed / (total - neutral)` and the
culture is to gate at 100%. Evilution's score is:

```
score = killed / (total - errors - neutral - equivalent - unresolved - unparseable)
```

i.e. only `killed / (killed + survived + timed_out)`. It defaults to a `min_score` of
`0.0` (no gate) — set your own threshold in CI with `--min-score`.

**Extra statuses** Evilution reports that mutant has no equivalent for:

- `unresolved` — no spec file mapped to the mutated source (coverage gap, excluded from score)
- `unparseable` — the mutated source did not parse, so it never ran (excluded)
- `equivalent` — proven behaviorally identical to the original (excluded)
- `timeout` / `error` — surfaced explicitly per mutation

**Exit codes:** `0` pass · `1` score below `--min-score` (survivors to address) · `2` error.

## 6. Verify the migration with `compare`

`evilution compare` ingests **both** a mutant session JSON and an Evilution JSON
report, normalizes them to a common shape, and buckets the mutations so you can see
whether the same code is being killed:

```sh
# produce an evilution report
bundle exec evilution run lib/ --format json --save-session

# line it up against your last mutant session JSON
bundle exec evilution compare \
  --against .mutant/results/<session-id>.json \
  --current .evilution/results/<timestamp>.json \
  --format text
```

The tool auto-detects which file came from which tool. Because the two tools use
different operator sets, expect the mutation **counts** to differ — the useful signal
is which subjects lose or gain coverage, not an exact 1:1 match. Operator names are
absent from mutant's JSON, so comparison keys on file + line + normalized diff, not on
operator.

## 7. Known gaps & parity notes

- **Different mutations.** Evilution ships its own operator registry (`--profile
  default` / `strict`); it is not mutant's AST-handler set. Counts and specific
  survivors will differ. Use `compare` to quantify.
- **No diff-based selection** (`--since <ref>`). Use file args, `--target source:`,
  or `--incremental`.
- **File-driven, not subject-driven.** Always pass paths; narrow with `--target`.
- **100%-coverage culture.** Evilution does not assume a 100% gate; choose `min_score`
  deliberately, and note that `:unresolved` mutations are excluded from the score
  rather than counted as failures.
- **Operator names** appear in Evilution output but not mutant's, so cross-tool diffs
  match on location + change, not operator identity.

If something you relied on in mutant has no clear equivalent here, please open an issue
— parity feedback directly shapes the 1.0 roadmap.
