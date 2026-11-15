# Combined-runs spike harness

Measurement scripts behind [`docs/combined_runs_spike.md`](../../docs/combined_runs_spike.md).
Nothing here is loaded by the gem. The harness is injected into an `evilution
run` with `RUBYOPT=-r<path>/combined.rb`.

| File | What it does |
|---|---|
| `combined.rb` | The harness: plans groups of mutants with disjoint covering examples, runs each group in one forked process, falls back to single runs. Settings via `EV_COMBINED*` variables, listed at the top of the file. |
| `run.sh` | Runs one target in control (`c`) or combined (`x`) mode and writes `<target>-<tag>.json`, `.stats.json` and `.err`. |
| `sum.rb` | One summary line per run. |
| `div.rb` | Mutants whose verdict differs between a control and a combined run. |
| `analyze.rb` | Cost of the group phase against the same mutants' single runs. |
| `rest.rb` | Cost of the mutants not handled in groups. |
| `ideal.rb` | Process count per group cap if every group ran cleanly. |
| `fm/` | The constructed project behind the false-kill and timeout failure modes. |

## Setup

Make a corpus directory outside the repository (`$CORPUS`) holding:

- `fixture/`: a copy of `spec/support/fixtures/benchmark_project`, with
  `gem "evilution", path: "<evilution checkout>"` added to its Gemfile.
- `fm/`: a copy of `fm/` from here. Its Gemfile reads the checkout from
  `EVILUTION_PATH`.
- `dry-monads/`, `httparty/`, `grape/`: clones at the commits pinned in
  `scripts/benchmark_perf.yml`, each with a `Gemfile.spike` that is the
  target's Gemfile plus the same `gem "evilution", path: ...` line.
  In httparty, make the cwd-relative fixture paths absolute
  (`spec/spec_helper.rb` `file_fixture`, and the `tiny.gif` path in
  `spec/httparty_spec.rb`), because mutation processes run in a sandbox
  directory.

Run `bundle install` in each copy (with `BUNDLE_GEMFILE=Gemfile.spike` for the
cloned targets).

## Running

```
export CORPUS=/path/to/corpus EVILUTION_PATH=/path/to/evilution
scripts/combined_runs_spike/run.sh fix c1 c          # control
scripts/combined_runs_spike/run.sh fix x1 x          # combined
scripts/combined_runs_spike/run.sh hp xc4 x EV_COMBINED_CAP=4
ruby scripts/combined_runs_spike/div.rb $CORPUS/out/fix-c1.json $CORPUS/out/fix-x1.json
ruby scripts/combined_runs_spike/analyze.rb $CORPUS/out/fix-c1.json $CORPUS/out/fix-x1.json
```

Alternate control and combined runs on the same tree; the report compares
three of each per target.
