# Mutant schemata spike harness

The measurement code behind [`docs/mutant_schemata_spike.md`](../../docs/mutant_schemata_spike.md).
It is measurement-only: like the rest of `scripts/` it is in the gem's file
list, but nothing under `lib/` requires it. It is loaded into a normal
`evilution run` from outside with `RUBYOPT=-r<file>` and patches evilution
internals by `prepend`, so it may stop working when those change. It is kept
so a next attempt (expression-level switching, pre-fork GC) can start from
what was measured. Since the measurements it has had style fixes only; a
re-run on i18n gave the same eligibility counts and verdicts.

## Files

| File | What it is |
|---|---|
| `schemata.rb` | The prototype: builds the switched meta-methods in the parent and makes `MutationApplier` set/clear the switch. Also carries the GC, re-eval, parent warm-up and constant-pinner memo probes (switches below). |
| `apply_prof.rb` | Timing wrapper: appends `step<TAB>ms<TAB>GCs` per call of each `apply` step to `$APPLY_PROF`. |
| `apply_prof_summary.rb` | Summarises an `apply_prof.rb` file per step (mean, p50, p90, GCs). |
| `gc_summary.rb` | Summarises an `EV_GCSTAT` file (GC ms, GCs and major GCs per mutant). |
| `run_totals.rb` | Per-run totals from JSON reports: duration, killtime and summed `apply` / `test_run` / `confirmation`. |
| `timing_distribution.rb` | Per-mutant distribution (mean, p10/p50/p90, max) of `apply`, `test_run`, `duration` and isolation overhead in one JSON report. |
| `compare_verdicts.rb` | Matches two JSON reports by file, line, operator and diff and prints the differing statuses. |
| `apply_bench.rb` | Micro-benchmark of syntax check, constant-name parse and eval of one file, in the parent and in a fresh fork child. |
| `switch_bench.rb` | Micro-benchmark of the per-call cost of the `case` switch. |

## Environment switches (`schemata.rb`)

| Variable | Effect |
|---|---|
| `EV_SCHEMATA=1` | Build the meta-methods in the parent after `MutationExecutor#warm` and switch eligible mutants instead of evaluating them. Unset: the harness only patches, every mutant takes the eval path. |
| `EV_SCHEMATA_STATS=<path>` | Write the eligibility counts, build time and parent RSS growth as JSON (with `EV_SCHEMATA=1`). |
| `EV_SCHEMATA_REEVAL=1` | Probe: also re-evaluate the file's meta-methods inside each mutation process, so the tests run freshly compiled copies. |
| `EV_SCHEMATA_GC=1` | Probe: run `GC.start` inside each mutation process after setting the switch, before the tests. |
| `EV_PARENT_WARMUP=1` | Probe: call `Process.warmup` (full GC, compaction, heap trim) in the parent after warm-up and the meta-method build, before anything forks. Works with schemata on or off. |
| `EV_GCSTAT=<path>` | Append `gc_ms<TAB>gcs<TAB>major_gcs<TAB>call_ms` per mutation (measured around `Integration::Base#call`) to the file. |
| `EV_PIN_MEMO=1` | The alternative: parse each original source's constant names once in the parent and reuse them in `ConstantPinner`. |

`apply_prof.rb` takes `APPLY_PROF=<path>`.

## Running

Targets were the pinned dry-monads and i18n canaries (see
`scripts/benchmark_perf.yml`) and `spec/support/fixtures/benchmark_project`,
each with a separate Gemfile that adds
`gem "evilution", path: "<evilution checkout>"`. The harness must be loaded
after Bundler, which `bundle exec` takes care of. Example (i18n, in its
checkout):

```
BUNDLE_GEMFILE=Gemfile.evilution RUBYOPT="-Itest -r<checkout>/scripts/schemata_spike/schemata.rb" \
  EV_SCHEMATA=1 EV_SCHEMATA_STATS=stats.json EV_GCSTAT=gc.tsv \
  bundle exec evilution run lib/i18n/backend/base.rb --spec test/i18n_test.rb \
  --integration minitest --preload test/test_helper.rb --jobs 2 --format json --no-progress > on.json

ruby <checkout>/scripts/schemata_spike/run_totals.rb off.json on.json
ruby <checkout>/scripts/schemata_spike/compare_verdicts.rb off.json on.json
ruby <checkout>/scripts/schemata_spike/gc_summary.rb gc.tsv
```

Alternate the configurations being compared (off, on, off, on, ...) and
repeat each several times: single runs on the same machine vary by about
10%.
