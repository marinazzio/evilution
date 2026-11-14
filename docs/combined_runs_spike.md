# Combined runs: spike report

Status: **no-go**. No prototype in `lib/`. The prototype was a harness
loaded from outside the gem (see [Reproducing](#reproducing)). The corpus
gate was met, but a constructed example shows the method can report a
survivor as killed, and the coverage map cannot rule that out. See
[Decision](#decision) for what would have to change first.

## Idea

Running several mutants in one process only pays if one run gives a verdict
for each of them. Naive grouping (apply k mutants, run their tests once) does
not: with 85–95% of mutants killed, a group almost always fails, and nothing
says which member caused it.

The variant tested here uses the per-example coverage map
(`--example-targeting coverage`, RSpec only). Mutants are combined only when
the sets of examples that execute their changed lines are disjoint. The union
of their targeted examples runs once. Each failing example executes the
changed lines of exactly one member in the original code, so its failure is
attributed to that member. A member with no failing example is not called a
survivor on that basis. It falls back to a single run.

## Prototype

A harness (`RUBYOPT=-r<harness>`) that prepends `MutationExecutor#run_batch`.

**Eligibility.** A mutant can join a group when all of these hold:

- it gets no verdict without a run (not unparseable, not `uncovered`, not
  implied by a probe sentinel);
- its file is built in the map;
- the examples covering its reported line are known, so its single run would
  be coverage-targeted and not lexical;
- every changed line that ran at all ran inside some example. A line that
  only ran while the file loaded (a constant, a class-body call, a `def`
  signature) can reach any example, so its mutant is not eligible.

Its *affecting set* is the union of the examples covering its changed lines.

**Grouping.** Greedy first fit, in the run's own order. A mutant joins the
first group where it overlaps no member's affecting set and, within the same
file, no member's changed byte range (a touching range counts as
overlapping). An optional cap limits members per group. An optional rule
puts at most one mutant of each subject in a group.

**Group run.** One forked process per group, `--jobs` of them at a time, with
a sandbox directory and the isolated-worker flags as in `Isolation::Fork`.
In that process:

- All members are applied. Members in the same file are merged: their
  changed regions of the neutralized source are spliced into one source,
  which `MutationApplier` evaluates once.
- The union of the members' targeted examples runs once, ordered
  killer-first as a single run would be. The parent records each group's
  kills in the kill history as the group finishes, so later groups and the
  remaining single runs start with those killers.
- **Per-member stop on kill.** An `around(:each)` hook skips the remaining
  examples of a member that has already been killed. When every member is
  killed, the run stops.
- The time limit is the sum of the members' limits.

**Fallback.** These cases go back to a normal single run (targeted run,
then confirmation):

- a group that failed to apply, crashed, timed out, or failed outside any
  example (a spec file that did not load, a context hook);
- a failure whose example belongs to no member;
- a member whose only failures were infrastructure crashes.

A member that passed its targeted examples in a clean group goes straight to
the confirmation run over its whole resolved spec file ("direct
confirmation"). Its targeted examples already passed once.

Killed members are reported `killed`, with the killing example and their
share of the group's duration.

## How many mutants combine

Measured from the plan on each target. Coverage targeting, `--isolation fork`
and `--jobs 2` throughout. "Processes" counts the forked processes that
decide a verdict. *Ideal* assumes every group runs cleanly and only the
members a single run did not kill fall back.

| Target | Mutants (run) | Eligible | Main reasons not eligible | Groups (no cap) | Members grouped | Mean size | Processes: single → ideal |
|---|---|---|---|---|---|---|---|
| fixture (3 files) | 440 (440) | 369 | reported line not attributed: 71 | 83 | 343 | 4.1 | 440 → 226 (**−49%**) |
| dry-monads `maybe.rb` | 610 (561) | 287 | line not attributed: 274; uncovered: 49 | 46 | 267 | 5.8 | 561 → 377 (**−33%**) |
| httparty `httparty.rb` | 1412 (1203) | 920 | line not attributed: 283; uncovered: 209 | 157 | 818 | 5.2 | 1203 → 656 (**−45%**) |
| grape `declared_params_handler.rb` | 691 (691) | 618 | line not attributed: 73 | 17 | 34 | 2.0 | 691 → 677 (**−2%**) |

A cap barely changes these numbers above 8 members. With the ideal process
count, cap 2 / 4 / 8 / none give −19 / −27 / −31 / −33% on dry-monads and
−26 / −42 / −45 / −45% on httparty. Grape gains almost nothing: every
endpoint example of `declared_spec.rb` runs through most of the file, so
almost no two subjects have disjoint example sets. How much can be combined
depends on how narrowly the target's examples exercise it, not on the kill
rate.

"Line not attributed" covers mutants reported at a line that no single
example is credited with: method-body mutants reported at their `def`, and
endless `def`s. Their single run uses lexical targeting, so they cannot join
a group.

## Results

### Verdicts

Each mutant was matched by file, line, operator and diff against a single-run
control on the same tree with the same flags. The control was run 2–4 times
per target.

| Target | Combined runs | Divergent verdicts | Control vs control |
|---|---|---|---|
| fixture | 5 (one without direct confirmation) | **0 / 440** each | 0 |
| dry-monads `maybe.rb` | 3 (one without direct confirmation) | **0 / 611** each | 0 |
| httparty | 6 (also cap 4, distinct subjects, no direct confirmation) | **0 / 1412** each | 0 |
| grape | 2 | **0 / 693** each | 0 |

That is 16 combined runs and 0 divergences on about 12,000 mutant verdicts,
so **the gate as stated is met**.

The first dry-monads run had 16 divergences. They were not caused by
combining. They came from a bug in coverage targeting, which also produces
wrong verdicts in the control (see [Found along the way](#found-along-the-way)).
The harness now treats a failure outside any example as a group failure, so
those groups fall back, and later runs reproduce the control exactly.

### Process count and time

Durations are `summary.duration` in seconds. The two modes were alternated
on the same tree.

| Target | Single runs | Combined | Change | Processes (measured) |
|---|---|---|---|---|
| fixture | 53.6, 53.4, 54.8 | 50.3, 50.6, 49.9 | **−7%** | 440 → 226 |
| fixture, without direct confirmation | (same) | 57.2 | +6% | 440 → 226 |
| dry-monads `maybe.rb` | 45.3, 46.3, 46.2 | 39.4, 39.2 (40.0 without direct confirmation) | **−14%** | 561 → 532 |
| httparty | 83.8, 85.4, 86.3 | 55.2, 56.0, 56.4 | **−34%** | 1203 → 656 |
| httparty, cap 4 / distinct subjects / no direct confirmation | (same) | 59.6 / 56.8 / 56.7 | −30% / −33% / −33% | |
| grape | 54.6, 54.4 | 52.6, 53.4 | −3% (noise) | 691 → 677 |

Where the time goes:

- **httparty.** A killed mutant costs 128 ms on average in a single run. Of
  that, 107 ms is `test_run`, and only 1.75 examples run per kill. The cost is
  almost all fixed per-process work (fork, sandbox, apply, RSpec setup, reap),
  not examples. Single runs spent 91.3 s of killtime on the 704 mutants that
  groups killed. The 157 group runs that replaced them took 33.3 s, even
  though they went through more examples (5841, skipped ones included, vs 1095). Grouping pays when the fixed
  cost per process outweighs the examples it adds.
- **fixture.** Each example sleeps 50 ms, so examples dominate. The 83 groups
  cost 45.4 s, against 46.1 s for the same 297 kills in single runs. Process
  count halved, examples gone through rose from 489 to 1849 (skipped ones included), and time stayed flat.
  The whole −7% comes from direct confirmation: 46 group survivors skipped
  their targeted run (50.8 s → 37.2 s). Without it the fixture is 6%
  *slower*.
- **dry-monads.** 22 of 46 groups failed outside any example, because of the
  shared-example targeting bug below. 9 more failed to apply: dry-monads turns
  Ruby warnings into errors, and merged sources raised "assigned but unused
  variable" warnings. Only 75 members were killed in groups, saving about
  6.5 s of killtime. The rest of the measured gain was in mutants that still
  ran singly: in all three combined runs they ran fewer examples (1006 vs
  1092–1128 for the singly killed ones), consistent with groups filling the
  kill history first. The ideal −33% process count is out of reach until that
  bug is fixed.
- **Ordering.** The kill history matters to groups. With an empty history
  (the first prototype recorded kills only after all groups had run), the
  fixture's group phase took 26.9 s. Recording kills as each group finishes
  brought it down to 22.8 s.

## Failure modes

**Shared or global state between subjects (false kill, demonstrated).**
Disjoint example sets say nothing about state that outlives an example. In a
constructed project, `Writer#with_entry` deletes its key in `ensure`, and
`Reader#read` has a survivor (`return :none if false`). In a single run,
`Writer`'s mutants `STORE.delete!(key)` and `STORE.delete` are killed, but
they leave the key in the store. Grouped with the `Reader` survivor, the
leaked key makes `Reader`'s example fail. The failure is attributed to the
`Reader` mutant, which is reported **killed**. A single run reports it
survived. Two of the 109 mutants in that project diverged this way.

**Control flow into another member's code (false kill, demonstrated).** The
map is built from the original code. A mutant can send its example into code
that the example never reached before, including another member's mutated
code. In the same project, `Router#route` is mutated from `n > 0` to
`n == 0`, which routes `route(5)` into `Helper#label`. On its own the mutant
survives, because the original `label(5)` returns `:positive`. Grouped with a
`Helper#label` mutant that returns `nil`, `Router`'s example fails, and the
`Router` mutant is reported killed. One more divergence. The
distinct-subjects rule does not prevent either case: the members here are in
different classes.

Both cases produce a false kill, which is the worst error for a mutation
tool to make: it hides a gap in the tests, and no reader can reproduce it.
The corpus has none, but nothing in the method rules them out. A check that
each failing example executed only its own member's mutated lines would
catch the second case. It would not catch the first: the reader's example
runs only reader code.

**Load order and constants redefined, several mutants at once.** Each file
of a group is evaluated once, with its members merged, through the normal
`MutationApplier` (constant pinning, concern cleanup, redefinition
recovery). Groups spanning the fixture's three files gave identical verdicts.
The risk shows up in projects that turn warnings into errors. A merged source
can raise a warning that none of its members raises alone (dry-monads: 9 of
46 groups). The harness falls back on any apply error, so the cost is time,
not correctness. A single mutant whose load crashes is reported killed
(`load_crashed`). Inside a group the same crash only causes a fallback.

**Crashes, timeouts and infinite loops.** A group limited by the sum of its
members' limits loses all of that time when one member loops, and then every
member runs again on its own. In the constructed project, a `Looper` mutant
times out after 12 s on its own. Five groups containing one timed out after
30–50 s each, before their members re-ran. The run took **128 s instead of
39 s**. A tighter group limit (the largest member's limit plus a margin)
would cut the waste but risks timing out a slow but healthy group. The
corpus had no timeouts.

**Stop on kill.** A single run stops at its first decisive failure. A group
cannot stop at the first failure without losing the other members' verdicts,
so the prototype stops per member: it skips the remaining examples of a
killed member, and stops the run once all members are killed. A survivor in
a group still runs all of its targeted examples, and with that group's
duration, then pays its confirmation run as well. On the fixture, groups went
through 3.8 times as many examples (skipped ones included) as single runs did for the same kills.

**Killer-first ordering.** Groups need a filled kill history as much as
single runs do (see the fixture numbers above). The history fills while
groups run, so the order in which groups are dispatched matters too.

**`uncovered` and probe-first.** Mutants given a verdict without a run are
never grouped. Probe-first was not measured. It calls `run_batch` once per
batch (sentinels first), and grouping would work within each batch.

**Incremental cache.** The prototype ran with the cache off. A real
implementation would keep cached mutants out of groups, and would store each
group kill per member, with its killing example. That kill depends on which
mutants ran beside it, which the cache key does not record.

**The map itself.** Attribution is only as sound as the map. A stale map
must never be used: `MapStore` invalidates by file digest, and the run
fingerprint covers the helpers. Coverage from code the tests run in a
forked subprocess is lost, so such examples are missing from affecting sets.
Shared examples are recorded under the shared file (below).

## Found along the way

- **Coverage targeting runs shared examples by their definition file.** The
  map credits examples defined in a shared group to that group's own
  location (dry-monads: `spec/shared/applicative.rb:5`). A targeted run
  passes that location to RSpec, which loads the shared file on its own,
  redefines the shared group and runs nothing. On dry-monads, where warnings
  are errors, this reports **30 mutants of `maybe.rb` killed with 0 examples
  run**, and 11 more as errors, in the plain single-run control. Lexical
  targeting reports 10 of the line-92 mutants as survivors. This is a
  verdict bug in coverage targeting today, independent of combined runs.
  Worth its own issue.
- **Coverage targeting without `--preload` on the fixture.** The map builder
  child raised `uninitialized constant RSpec` (in `MapBuilder#reset_world`),
  and the run fell back to lexical targeting. Passing
  `--preload spec/spec_helper.rb` avoids it.

## Decision

**No-go** for now, neither as a default nor as an opt-in, for four reasons:

1. **The method is not sound, and the gate does not show that.** Zero
   divergences on the corpus is the stated gate, and it was met in 16 runs.
   But two mechanisms that turn a survivor into a kill (shared state between
   examples, control flow into another member's code) were shown on a
   constructed project. The coverage map cannot see either one, and the
   result is a false kill, which no reader can reproduce.
2. **The gain depends on the target.** −34% on httparty, where a kill costs
   more in process overhead than in examples. −7% on the fixture, all of it
   from skipping survivors' targeted runs. −3% (noise) on grape, whose
   examples cover almost the whole file. −14% on dry-monads, where most
   groups fell back.
3. **Failures are expensive.** A looping member costs its group the sum of
   the members' limits, and then everyone runs again (39 s → 128 s on the
   constructed project). Merged sources raise warnings that no single
   mutant raises, and in a project that turns warnings into errors the whole
   group falls back.
4. **It is RSpec and coverage-targeting only,** and the shared-example bug
   above currently makes coverage targeting give wrong verdicts on one of
   the corpus targets.

What would make it worth revisiting:

- the shared-example targeting bug fixed;
- an attribution check: kill a member only if every failing example
  executed that member's mutated lines and no other member's, which closes
  the control-flow case;
- groups limited to members whose examples share no mutable state. Nothing
  measured here can tell that; marking specs that run in random order and
  isolation is the closest available signal;
- a group time limit tighter than the sum of the members' limits.

Even then, a group kill would be the only verdict evilution gives that a
single run cannot reproduce. Re-running each group kill alone to check it
would cost exactly what grouping saves.

## Reproducing

Corpus: scratchpad copies of the fixture and of `/tmp/ev-canaries/{dry-monads,httparty,grape}`
(pinned commits in `scripts/benchmark_perf.yml`). Each copy has a Gemfile
adding `gem "evilution", path: <tree>`. In httparty, the cwd-relative fixture
paths are made absolute (`spec/spec_helper.rb` `file_fixture`, and the
`tiny.gif` path in `spec/httparty_spec.rb`), because mutation processes run
in a sandbox directory.

Harness, loaded with `RUBYOPT=-r<file>` (it requires `bundler/setup` and
`evilution` first):

- A module prepended to `Evilution::Runner::MutationExecutor` whose private
  `run_batch(notifier, pipeline, mutations, baseline_result, integration)`
  plans the groups, as described under [Prototype](#prototype). It reads the
  map from the integration's `CoverageExampleFilter`, and it decides
  eligibility from `Coverage::Map#examples_for` / `#executed?` over
  `mutation.changed_lines`. Group runs are forked by the harness, `--jobs`
  at a time. Then `super` handles the rest, and the two `ExecutionResult`s
  are merged.
- Merging within a file: each member's change is the common prefix and
  suffix of `restore_source` against `eval_source` (and of
  `original_source` against `mutated_source`). Non-touching ranges are
  spliced into one `Evilution::Mutation`, which the integration's
  `MutationApplier` evaluates.
- A module prepended to `Evilution::Integration::RSpec` whose `run_tests`
  goes straight to `confirm_run` for members that passed in a clean group.
- `EV_COMBINED=1` runs groups (otherwise plan only). `EV_COMBINED_CAP`,
  `EV_COMBINED_DISTINCT=1` and `EV_COMBINED_DIRECT_CONFIRM=0` select the
  variants. `EV_COMBINED_OUT` writes the plan, the per-cap groupings and the
  per-group outcomes as JSON.
- Verdict equivalence: match the two runs' JSON entries by file, line,
  operator and diff, and compare statuses.

Commands (in the target dir; the harness via `RUBYOPT`):

```
# fixture
bundle exec evilution run lib/pricing.rb lib/inventory.rb lib/grade.rb --preload spec/spec_helper.rb \
  --example-targeting coverage --isolation fork --jobs 2 --format json
# dry-monads
bundle exec evilution run lib/dry/monads/maybe.rb --spec spec/unit/maybe_spec.rb --integration rspec \
  --preload spec/spec_helper.rb --example-targeting coverage --isolation fork --jobs 2 --format json
# httparty
bundle exec evilution run lib/httparty.rb --spec spec/httparty_spec.rb --integration rspec \
  --preload spec/spec_helper.rb --example-targeting coverage --isolation fork --jobs 2 --format json
# grape
bundle exec evilution run lib/grape/declared_params_handler.rb --spec spec/grape/endpoint/declared_spec.rb \
  --integration rspec --preload spec/spec_helper.rb --example-targeting coverage --isolation fork \
  --jobs 2 --format json
```

The constructed project behind the failure modes is one file:

- a `STORE` hash;
- `Writer#with_entry` (set the key, yield, delete it in `ensure`);
- `Reader#read` (with an untested `nil` guard);
- `Router#route` (`n > 0 ? :positive : Helper.new.label(n)`);
- `Helper#label` (`n.positive? ? :positive : :other`);
- `Looper#count` (`i += 1 while i < n`).

It has one example per subject, and two for `Helper`. i18n and Redmine were
left out: they are Minitest, and the coverage map is RSpec only.
