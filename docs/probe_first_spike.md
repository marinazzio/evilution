# Probe-first per subject: spike report

Status: **opt-in prototype** (`--probe-first` / `probe_first: true`, off by
default). Decision at the end.

## Idea

Run one sentinel mutant per subject before the others: the method's whole body
replaced by a bare `raise` (`method_body_to_raise`). If even that survives, no
selected test calls the method on a path it checks, and the subject's other
mutants (10–50 per method) would almost all survive too, after a full run and a
[survivor confirmation](../README.md#survivor-confirmation) run each. Report them
as survivors implied by the sentinel, without running them.

The same idea one level down: run `statement_deletion` of each statement first,
and when deleting the statement survives, skip the other mutants inside it.

## Prototype

- `Runner::MutationExecutor::ProbeFirst` picks the sentinel (the
  `method_body_to_raise` mutant reported at the subject's own line), records
  its verdict and answers which mutants it implies. A sentinel that survived or
  is `uncovered` implies; killed, timeout, error, neutral do not. Subjects
  without a sentinel (empty body, a body that is a single `raise`, constants,
  class-body declarations) are never skipped.
- `Runner::MutationExecutor::ProbeFirstRun` runs two batches through the
  unchanged sequential or parallel strategy: all sentinels, then the rest. One
  notifier spans both, so progress, `--fail-fast` and the logs see one run;
  results come back in the original order.
- `RunlessVerdict` reports an implied mutant `survived` with
  `implied_by: "method_body_to_raise"` (JSON field), without a run, the same way
  it already reports `unparseable` and `uncovered`. Implied survivors are not
  cached and get no confirmation run. `probe_first` joins the incremental
  cache's run fingerprint.
- The statement level was measured by simulation only (below); it was not
  built, because the simulation already rules it out.

## Method

Corpus: the `scripts/benchmark_perf.yml` targets, on scratchpad copies of
`/tmp/ev-canaries`, `--jobs 2` (Redmine `--jobs 1`), one run each:

| Target | File | Tests |
|---|---|---|
| dry-monads | `lib/dry/monads/list.rb` | `spec/unit/list_spec.rb` (RSpec) |
| httparty | `lib/httparty.rb` | `spec/httparty_spec.rb` (RSpec) |
| grape | `lib/grape/declared_params_handler.rb` | `spec/grape/endpoint/declared_spec.rb` (RSpec) |
| i18n | `lib/i18n/backend/base.rb` | `test/i18n_test.rb` (Minitest) |
| redmine | `app/models/tracker.rb` | `test/unit/tracker_test.rb` (Minitest) |
| httparty, fixed | as httparty, with the cwd-relative fixture path in the spec made absolute | |
| dry-monads `maybe.rb` (extra) | `lib/dry/monads/maybe.rb` | `spec/unit/maybe_spec.rb` (RSpec) |

Per target: a full run (the verdicts every other number is checked against),
the same with `--probe-first`, and for the RSpec targets both again with
`--example-targeting coverage` (where `uncovered` applies). Mutants are matched
across runs by file, line, operator and diff.

- **Divergence**: implied survivors that the full run killed or timed out.
- **Time saved**: the summed `duration` of the implied mutants in the full run
  (`killtime` saved); wall time from runs with the flag off and on alternated
  (below), since the machine was shared with another long benchmark and
  single runs taken at different times differed by up to 2x with nothing
  implied at all.
- The statement level is simulated on the full run: a surviving
  `statement_deletion` covering lines a..b implies every other mutant reported
  on a..b.

### Corpus artifacts

- **httparty**: `spec/httparty_spec.rb:226` opens `spec/fixtures/tiny.gif` by a
  cwd-relative path, which raises `Errno::ENOENT` in the per-mutation sandbox.
  Every mutant run against that example is "killed" (1412/1412 in the full
  run), so every sentinel is killed and probe-first implies nothing. The
  "httparty, fixed" copy makes the path absolute; its numbers are the ones that
  count.
- **dry-monads `list.rb`**: re-evaluating the mutated file re-runs class-body
  lines that cannot run twice, so every mutant is killed (0 survivors in every
  run). Probe-first implies nothing there either.

## Results: subject level (`method_body_to_raise`)

Lexical targeting (the default). "Killtime saved" is the summed duration, in
the full run, of the mutants the probe-first run reported without running
them.

| Target | Mutants | Sentinels survived | Implied survivors | Of those, killed in the full run | Killtime saved |
|---|---|---|---|---|---|
| i18n | 1837 | 10 / 19 | 871 | **0** | 37.2 s of 79.1 s (47%) |
| httparty, fixed | 1412 | 17 / 62 | 206 | **0** | 37.5 s of 226.1 s (17%) |
| dry-monads `maybe.rb` (extra) | 611 | 11 / 35 | 114 | **0** | 15.0 s of 96.6 s (16%) |
| redmine | 500 | 1 / 12 | 3 | **0** | 1.9 s of 240.4 s (1%) |
| grape | 693 | 0 / 11 | 0 | – | 0 |
| httparty (artifact) | 1412 | 0 / 62 | 0 | – | 0 |
| dry-monads `list.rb` (artifact) | 923 | 0 / 35 | 0 | – | 0 |
| **Total** | 7388 | 39 / 236 | **1194** | **0** | |

`maybe.rb` was added because `list.rb`, the corpus' dry-monads target, kills
every mutant (see artifacts). The implied sets of the probe-first runs agree
with a simulation on the full runs (httparty 206 = 206, i18n 871 vs 867,
`maybe.rb` 114 vs 107; the simulation guesses each subject's span from line
numbers).

No implied survivor was killed in any full run: **divergence 0 of 1194**. The
case that would diverge -- a test that rescues the sentinel's `RuntimeError`
around the call, or a matcher that expects some error, while a value mutant of
the same method is still caught -- did not occur in this corpus.

### Overlap with `uncovered` (coverage targeting)

Both detect code no test exercises. With `--example-targeting coverage` (RSpec
only), `uncovered` already takes every mutant whose changed lines never ran,
so the sentinel itself is usually `uncovered` and what probe-first adds is the
mutants on lines that ran at load time: the `def` line (default argument
values, `optional_parameter_to_required`, `block_param_removal`) of a method
nobody calls, and lines coverage cannot vouch for.

| Target | `uncovered` | Probe-first implied on top | Their full-run verdict | Killtime saved on top |
|---|---|---|---|---|
| httparty, fixed | 209 | 21 | 21 survived | 3.9 s (1.7%) |
| dry-monads `maybe.rb` | 49 | 67 | 67 survived | 8.9 s (9.2%) |
| grape | 0 | 0 | – | 0 |
| httparty (artifact) | 209 | 21 | 21 "killed" (artifact) | – |
| dry-monads `list.rb` (artifact) | 33 | 3 | 3 "killed" (artifact) | – |

On the artifact targets the 24 implied mutants on top of `uncovered` are the
`def` lines of methods coverage shows are never called; the full run "kills"
them only through the artifacts (the fixture crash, the class-body re-run),
the same way it "kills" their `uncovered` neighbours. On the fixed httparty
copy the same 21 mutants survive.

So with coverage targeting probe-first adds little (2-9% of killtime). Its
value is where `uncovered` cannot reach: **Minitest and test-unit** (i18n and
redmine above, 47% and 1%), and RSpec runs that keep lexical targeting.

## Results: statement level (`statement_deletion`), simulated

| Target | Implied | Of those, killed in the full run |
|---|---|---|
| i18n | 818 | 60 (7%) |
| httparty, fixed | 92 | 16 (17%) |
| dry-monads `maybe.rb` | 53 | 11 (21%) |
| grape | 47 | 9 (19%) |
| redmine | 49 | 19 (39%) |

Deleting a statement that survives does not mean the statement is not
executed. The typical case is a guard: `raise ArgumentError, "..." unless
fields.is_a?(Array)` or `return if arg.blank?` can be deleted because no test
passes the bad input, but negating its condition makes it fire on good input
and is killed at once. Statement-level probing would hide real kills on every
target: **no-go**.

## Wall time

Same evilution tree, `--probe-first` off and on alternated, two runs each
(seconds; the machine was shared with another benchmark, so single runs vary
by about 10%):

| Target | Off | On | Change |
|---|---|---|---|
| i18n, `--jobs 2` | 44.7, 45.3 | 22.8, 23.9 | **-48%** |
| i18n, `--jobs 1` | 83.9, 82.1 | 41.4, 39.2 | **-50%** |
| httparty, fixed, `--jobs 2` | 141.3, 127.3 | 114.4, 118.2 | **-13%** |
| grape, `--jobs 2` (nothing implied) | 65.9, 70.8 | 69.8, 69.7 | none (noise) |

The wall time saved follows the killtime saved, and a little more: an implied
survivor also skips its survivor confirmation run. Verdicts and scores were
identical in every pair. (An interleaved `scripts/benchmark_perf` run of the
`HEAD` export against the worktree with `--probe-first`, three repeats, gave
the same picture: i18n -43% / -51%, httparty fixed -14%, 0 lost kills; it also
showed grape 14% faster with nothing implied, which the same-tree pair above
does not, so that run's deltas carry a difference between the two trees and
the table above is the one to read.)

Where nothing is implied (grape, the fixture project, redmine) probe-first
costs nothing measurable: the sentinels are mutants the run had anyway, and
only their order changes.

## Parallel runs (`--jobs`)

The prototype runs two batches, so a parallel run has a barrier: once the
sentinel queue is empty, workers idle until the last sentinel is done, and the
second batch starts a fresh pool.

- Measured at `--jobs 2`: idle time at the barrier (worker wall minus busy
  time in the first pool) was 0.02–0.24 s per worker; the sentinel batch took
  0.3 s (i18n), 1.1 s (grape), 2.8 s (`maybe.rb`), 5.3 s (httparty) of
  22–101 s of execution; starting the second pool, about 0.04 s. Under 1% of
  wall in every case, and i18n saves the same share at `--jobs 1` (no
  barrier) as at `--jobs 2`.
- The barrier is bounded by one sentinel per worker, so it grows with
  `--jobs` and with slow sentinels: the worst case is a sentinel that runs
  into its time limit (an infinite loop the body-raise cannot cause, but a
  slow spec file can), which holds every other worker for that long. A run
  with fewer subjects than workers also leaves workers unused in the first
  batch.
- The alternative without a barrier is one streaming queue with the
  sentinels first, the decision made when the pool hands a mutant out (as
  killer hints already are, `Strategy::Parallel::HintedItems`), and the
  runless partition moved from before the run to dispatch time. A mutant
  handed out while its sentinel is still running would then simply run
  (correct, just not skipped): at most `jobs - 1` per subject, for the last
  subjects only. Not built: the measured barrier is too small to pay for
  moving the partition.
- A side effect: the sentinels' kills reach the kill history before the
  other mutants of their subject run, so killer-first ordering has a killer
  for every exercised subject from the start. No gain could be measured on
  grape.

## Decision

- **Statement level (`statement_deletion` as sentinel): no-go.** 7–39% of the
  mutants it would skip are killed by a full run, on every target.
- **Subject level (`method_body_to_raise` as sentinel): go, as an opt-in.**
  Divergence 0 of 1194 implied survivors. On the targets with untested
  methods worth the name it saves 13–50% of wall time (i18n -48%, httparty
  -13%) and 16–47% of killtime (`maybe.rb` 16%); it costs nothing measurable
  where there are none. It
  stays behind `--probe-first` / `probe_first: true`, marked experimental in
  the README, and joins the incremental cache's run fingerprint.
- **On by default: not yet.** Only four of seven targets had a single
  unexercised method, so 0 divergences is evidence from few subjects (39
  sentinels that survived); the case that would diverge (a caller that
  rescues the sentinel's error) is common in real code and absent here; an
  implied survivor has no `test_command` or confirmation run of its own; and
  with RSpec coverage targeting `uncovered` already reports most of the same
  mutants (185 of 206 on httparty, 47 of 114 on `maybe.rb`). Revisit after a stability-matrix round run with
  `--probe-first` on, comparing its verdicts against a full run: if the
  divergence stays at 0, make it the default for runs without coverage
  targeting (Minitest and test-unit first, where nothing else skips untested
  code).

## Reproducing

Full runs and probe-first runs: `scripts/benchmark_perf` with one target per
setting (the `--probe-first` and `--example-targeting coverage` flags in the
target's `args`). Divergence: match the `implied_by` entries of the
probe-first run's JSON to the full run's by file, line, operator and diff,
and read the full run's verdict.
