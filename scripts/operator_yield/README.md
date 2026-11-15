# Operator yield study scripts

Measurement-only scripts behind [docs/operator_yield_study.md](../../docs/operator_yield_study.md).
They are not loaded by the gem and not packaged with it (`evilution.gemspec`
leaves this directory out).

| File | What it does |
| --- | --- |
| `killsets_hook.rb` | Loaded into an evilution run with `-r`. Records every failing test per mutant (`KILLSETS_OUT`), dumps every generated mutation before de-duplication (`GENERATED_OUT`, with `GENERATED_ONLY=1` to stop after planning), and drops operators (`DROP_OPERATORS`) or operator variants (`DROP_VARIANTS`). Inert without those variables. |
| `variants.rb` | Names the variant of a literal operator's mutation from its diff (`integer_literal:nil`, `integer_literal:width_sentinel`, `string_literal:empty`, ...). |
| `run_study.sh` | Runs the corpus: default runs, kill-set runs, generation dumps, and the A/B wall-time runs. |
| `analyze.rb` | Per-operator and per-variant tables, drop costs, the leave-one-target-out selection rule. |
| `ab_compare.rb` | The A/B table (mutants, killtime, wall time, score) and which operator reports a dropped operator's mutant when another one generates the same code. |

## Corpus

The study uses the `scripts/benchmark_perf.yml` corpus (clone, check out and
bundle each project as described there; Redmine also needs its test
database). Put the checkouts side by side in one directory, named `fixture`
(a copy of `spec/support/fixtures/benchmark_project`), `dry-monads`,
`httparty`, `grape`, `i18n` and `redmine`, and give each a Gemfile that loads
this repository's evilution next to the project's own gems:

```ruby
# <corpus>/<project>/Gemfile.operator_yield
eval_gemfile "Gemfile"
gem "evilution", path: "<path to this repository>"
```

then `BUNDLE_GEMFILE=Gemfile.operator_yield bundle install` in each. The
httparty and dry-monads adjustments the study made are described in its
Method section.

## Running

```sh
export CORPUS_DIR=<corpus dir> OUT_DIR=<output dir>

# default, kill-set and generation runs for every target
scripts/operator_yield/run_study.sh default nostop generated

# the tables
ruby scripts/operator_yield/analyze.rb $OUT_DIR \
  fx-pricing fx-inventory fx-grade dm-maybe hp grape i18n redmine \
  --variants integer_literal,string_literal,float_literal \
  --drop-each integer_literal:nil,integer_literal:width_sentinel,string_literal:empty \
  --drop conditional_flip,negation_insertion,string_literal:empty

# the selection rule, without Redmine (it is the held-out project)
ruby scripts/operator_yield/analyze.rb $OUT_DIR \
  fx-pricing fx-inventory fx-grade dm-maybe hp grape i18n --loto

# A/B wall time of a drop set (REPEATS alternated off/on runs per target)
DROP_SET=conditional_flip,negation_insertion,string_literal:empty REPEATS=2 \
  TARGETS="fx-grade dm-maybe grape i18n hp" scripts/operator_yield/run_study.sh ab
ruby scripts/operator_yield/ab_compare.rb $OUT_DIR conditional_flip,negation_insertion,string_literal:empty
```

`TARGETS` narrows any run to some targets; `CORPUS_GEMFILE` names the
per-project Gemfile (default `Gemfile.operator_yield`). Wall times go to
`$OUT_DIR/wall.log`. The hook must be given after `bundle exec` (as
`run_study.sh` does), not in `RUBYOPT`: it requires evilution, which has to
resolve through the bundle.
