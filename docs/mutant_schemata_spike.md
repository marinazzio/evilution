# Mutant schemata: spike report

Status: **no-go**. No prototype in `lib/`. The prototype was a harness
loaded from outside the gem, kept in `scripts/schemata_spike/` (see
[Reproducing](#reproducing)). Two cheaper
changes, found while measuring, are recommended instead
([below](#what-to-do-instead)).

## Idea

Mutation switching ("mutant schemata", Untch; Stryker's mutant switching):
build one meta-version of a file with every method-body mutant behind a
runtime switch, evaluate it once in the parent before any mutation process
forks, and have each mutation process only set the active mutant's id. That
removes the per-mutant parse, evaluate and restore of the whole file. Class
bodies, constants, visibility and load-time mutants keep the eval path.

## How much there is to save

The fixed cost schemata can remove is the `apply` phase of each mutation
(syntax check, constant pinning, concern cleanup, eval of the file; the
in-process restore too). It is not the isolation around it (fork, sandbox,
reap) or the test run. That phase was measured first, from the per-mutation
`timings` in the JSON report, on the current tree (everything up to the
operator yield study, so parse-once generation and warm parent caches are
already in). Each target ran at `--jobs 2`.

| Target | Isolation | Mutants | `apply` per mutant (mean / p50) | Isolation overhead per mutant | `test_run` per mutant | `apply` share of killtime |
|---|---|---|---|---|---|---|
| fixture (`spec/support/fixtures/benchmark_project`) | in_process | 440 | 0.40 / 0.40 ms | 0.8 ms | 32.8 ms (+ confirmation) | **0.1%** |
| dry-monads `lib/dry/monads/maybe.rb` | fork | 611 | 5.2 / 5.1 ms | 10.5 ms | 117 ms | **3.6%** |
| i18n `lib/i18n/backend/base.rb` (Minitest) | fork | 1837 | 8.3 / 7.9 ms | 9.5 ms | 22.5 ms | **20.5%** |

So the most schemata can win is what `apply` costs today, and that is only
large where the tests are fast (i18n: 22 ms per test run).

Where that `apply` time goes was measured by wrapping each step in a real
i18n run (mean per mutant, fork child):

| Step | ms |
|---|---|
| `ConstantPinner` (a full `Prism.parse` of the **original** file, to list its constants) | **6.08** |
| `SourceEvaluator` (the eval itself) | 0.96 |
| `SyntaxValidator` (`Prism.parse_success?`, no tree) | 0.37 |
| `mark_feature_loaded` | 0.12 |
| `ConcernStateCleaner` (no ActiveSupport here) | 0.01 |
| **Total `apply`** | **8.05** |

Three quarters of `apply` is the constant pinner building a full syntax tree
of the unchanged original file, in every mutation process, and getting the
same names each time. The same parse takes 0.5 ms in a warm parent; in a
freshly forked child it costs about 6 ms on almost every call (p50 6.0 ms).
GC is not the reason: only 26 of the 1831 calls ran a GC. The cost is per
call, in allocating the tree on the child's fresh heap and the copy-on-write
page faults of those first writes. The eval that schemata would remove costs
about 1 ms.

## Prototype

A harness (`RUBYOPT=-r<harness>`), not code in `lib/`. It prepends two hooks:

- **Parent**, after `MutationExecutor#warm`, before workers or mutation
  processes fork: per file, it takes each mutation's change as the common
  prefix and suffix of the neutralized original (`restore_source`) and its
  `eval_source`. A mutation is eligible when the change lies inside the body
  of a `def` that is nested only in `class`, `module` and `class << self`
  bodies (or wrapped in `private def ...`). Each such method is rebuilt as

  ```ruby
  def name(params)
    case $__evilution_schema when nil then begin <original body, on its own lines>
    end when 17 then begin
    <body with mutation 17>
    end when 18 then begin
    ...
    end else begin
    <original body>
    end end
  end
  ```

  and evaluated **on its own**, wrapped in the file's nesting written on the
  `def`'s line (`module I18n; module Backend; module Base; def ...`) and
  with the file's path and the `def`'s line number. Nothing else in the file
  runs again: no class body, no neutralizer, no `alias` line. Every line
  outside the variants keeps its number, and so does the original branch.
  After the redefinition it re-applies the method's visibility, its
  `module_function` copy and the file's `alias`/`alias_method`s of it.
  The redefinitions and re-aliases are wrapped in `ReevalWarningFilter`, since
  dry-monads' spec helper turns "method redefined" warnings into errors.
- **Mutation process**: `MutationApplier#call` sets `$__evilution_schema` to
  the mutation's id and returns. `#restore` clears it. Under `in_process`, a
  restore after a mutation of the same file that took the eval path puts the
  meta-methods back.

Not eligible: changes outside a static `def` body (constants, class-body
calls, signatures and default arguments, `def`s inside blocks such as
`included do`, `Module.new do`, `Class.new do`), endless `def`s (the
prototype did not rewrite them), scope/aasm/callback/concern-hook subjects
(their restore source keeps a declaration of their own), variants containing
`__LINE__`, `binding` or `local_variables`, and the local-variable conflict
described below.

## Correctness questions

**Which mutants.** Method bodies only, of `def`s reachable through
class/module/singleton-class bodies, including `def self.x` and
`class << self`. Blocks and lambdas inside a body are part of the body and
switch with it. Not covered: methods built by `define_method` (their body is
a block evaluated at load time; switching it means re-running the class-body
call), `def`s inside blocks (concern `included`/`class_methods`, `Module.new`,
`Class.new`, `Struct.new do`), and endless `def`s. Endless `def`s can be
rewritten to the long form (an extra 150 of 610 on `maybe.rb`).

**Methods redefined later in the file.** Each `def` gets its own switch, and
the later definition wins at load time, as it does when the file is
evaluated. Equivalent.

**Aliases.** `alias new old` copies the method entry at the moment it runs.
Evaluating the whole file re-runs the alias, so the alias gets the mutant.
Redefining one method does not. The prototype re-aliases the file's own
aliases of the method after redefining it. An alias made in another file
keeps the original under both paths. A load-time capture other than an alias
(`HANDLERS = { a: method(:foo) }`, `define_method(:b, instance_method(:a))`,
a memoizer that wraps by copying the method) keeps the original under
schemata but gets the mutant under the eval path, unless the neutralizer
blanked the capturing call. The prototype does not detect these: none
occurred on the targets, so it can only be counted as an open risk.

**Visibility and `module_function`.** A `def` in a reopened class is public.
The original visibility has to be read before the redefinition and set again
after it, and a `module_function` method's singleton copy has to be made
again. The prototype does both.

**Local variables across branches.** Ruby decides at parse time whether a
bare `x` is a local or a method call, by whether an assignment to `x` comes
before it in the method. In the meta-method every branch shares one local
table, so a variant that drops `x = compute` and keeps a later `x` turns
that `x` from a `NoMethodError`/`NameError` (eval path) into `nil`
(schemata). The prototype parses each variant and drops it when a bare call
in it names a local assigned in an earlier branch. That dropped 6 of 440
(fixture), 30 of 1830 (i18n) and 6 of 610 (`maybe.rb`).

**Source locations, `__method__`, `super`, `return`, `binding`.** `return`,
`yield`, `block_given?`, `super` (implicit and explicit), `__method__` and
`retry` in a body-level `rescue` behave the same inside `case ... begin ...
end`, because the branch is still the method's own frame. The original
branch keeps its lines. A variant's lines do not: they come after the
original body, so a backtrace from inside the active mutant, `__LINE__`, or
an exception message carrying a line differ from the eval path. Variants
using `__LINE__` were dropped. `binding` and `local_variables` see the
locals of every branch (as `nil`), so variants using them were dropped too.
`Method#source_location` points at the `def` line in both paths.

**Runtime cost of the switch.** One global read plus `opt_case_dispatch`
per call: a method doing `x + 1` went from 17 ns to 36 ns per call (+19 ns).
A frozen per-file array read instead of the global cost +10 ns. That is
negligible next to a method that does real work. It is paid on every call
in every mutation process, including calls of mutants of other methods.

**Isolation and workers.** Under `fork` (and the persistent workers, which
fork a process per mutation), the meta-version is built once in the parent
before the workers fork, and the mutation process only sets the global. Under
`in_process`, a schemata mutant needs no restore. An eval-path mutant of the
same file replaces the meta-methods with its own and must be followed by
the meta-methods, not just the original (the prototype does that). The
fixture ran in-process at `--jobs 2` with identical verdicts.

**Neutralizer and preload.** Redefining single methods sidesteps the
neutralizer entirely: no class body runs again. That is the main correctness
gain over evaluating a whole meta-file, which would re-run class bodies once
in the parent like any eval. The file must be loaded in the parent first
(preload does that for gems and Rails; the fixture's files were `require`d
by the harness). For Rails, a meta-method defined before workers fork is
inherited like any preloaded code. The prototype was not run on Redmine.

**Memory.** The parent's RSS grew by 0.8 MB (fixture), 0.25 MB (`maybe.rb`)
and **16.5 MB** (i18n `base.rb`: 1751 variants, most of them copies of a few
long methods). Building and evaluating them took 0.17 s, 0.31 s and **2.3 s**,
serially in the parent before the first mutation.

## Results

Eligible share (prototype rules):

| Target | Eligible | Outside a static `def` body | Endless `def` | Local conflict | `__LINE__`/`binding` |
|---|---|---|---|---|---|
| fixture | 409 / 440 (93%) | 25 | 0 | 6 | 0 |
| i18n `base.rb` | 1751 / 1830 (96%) | 26 | 0 | 30 | 23 |
| dry-monads `maybe.rb` | 395 / 610 (65%) | 59 | 150 | 6 | 0 |
| **Total** | **2555 / 2880 (89%)** | 110 | 150 | 42 | 23 |

(Mutants reported without a run, here the equivalent ones, never reach
`apply` and are not counted.)

**Verdict equivalence:** identical on every run. Each mutant was matched by
file, line, operator and diff against the eval-path run: fixture 440/440,
i18n 1837/1837 and dry-monads `maybe.rb` 611/611 (one schemata run for the
fixture, three for dry-monads, and every schemata run on i18n, probes
included).

**`apply` per mutant**, eval path vs schemata (mean, all mutants):

| Target | Eval path | Schemata | Saved per mutant |
|---|---|---|---|
| fixture | 0.40 ms | 0.11 ms | 0.3 ms |
| dry-monads `maybe.rb` | 5.2 ms | 2.5 ms (eligible: 0.1 ms) | 2.7 ms |
| i18n `base.rb` | 8.3 ms | 0.5 ms | 7.8 ms |

**Wall time and killtime**, same tree, schemata off and on alternated
(seconds):

| Target | Off: duration / killtime | On: duration / killtime | Change in duration |
|---|---|---|---|
| i18n, `--jobs 2` | 39.7 / 76.7, 40.2 / 77.7 | 42.8 / 80.0, 43.6 / 81.5 | **+8% (slower)** |
| dry-monads `maybe.rb`, `--jobs 2` | 45.3 / 88.8, 43.5 / 85.3, 43.8 / 85.8 | 44.9 / 87.3, 50.2 / 97.6, 43.3 / 83.9 | none measurable (`apply` saves 2.6 s of ~86 s killtime; one run on was a 15% outlier) |
| fixture, `--jobs 2` (one pair) | 77.7 / 149.7 | 83.9 / 160.8 | no gain possible: `apply` is 0.17 s of the run; the difference is in test and confirmation time |

On i18n, schemata removes 16 s of `apply` and adds 19 s of `test_run`
(42.2 / 42.8 s → 61.5 / 62.0 s). The tests themselves got slower. Four
measurements, all with verdicts identical to the eval path, narrow down
why:

- **GC per mutation process** went from 10.6 to 13.4 ms, and major GCs from
  0.115 to 0.258 per mutant, with the parent's heap 16.5 MB larger (one run
  each with GC counters).
- **Full GC in the parent before forking** (`Process.warmup` after the
  meta-methods are built: full GC, compaction, heap trim), three rounds
  alternated with schemata alone, the eval path alone and the eval path
  with the same warm-up. The machine was busier than in the runs above, so
  compare within this table only (means of three runs, seconds):

  | i18n, `--jobs 2` | duration | killtime | `test_run` | GC per mutant | major GCs per mutant |
  |---|---|---|---|---|---|
  | eval path | 48.0 | 92.6 | 51.5 | 12.2 ms | 0.14 |
  | schemata | 55.1 | 103.5 | 79.9 | 16.5 ms | 0.31 |
  | schemata + parent warm-up | 44.3 | 81.1 | 58.5 | 7.4 ms | 0.14 |
  | eval path + parent warm-up | 42.9 | 82.2 | 41.7 | 6.9 ms | 0.17 |

  The warm-up removes the GC penalty of the bigger heap: with it, the child
  spends about as long in GC under schemata as under the eval path. It does
  not remove the rest: `test_run` is still 16.7 s (9 ms per mutant) higher
  than the eval path with the same warm-up.
- **Re-evaluating the meta-methods inside each mutation process** (fresh
  copies compiled in the child, `apply` 252 s) brought `test_run` back to
  the eval path's 42 s. So the switch and the size of the methods do not
  slow the tests by themselves.
- **`GC.start` inside each mutation process**, after setting the switch and
  before the tests (`apply` 65 s), brought `test_run` down to 29.1 s, below
  the eval path's 42 s, because the tests then ran with no GC debt at all.
  A full GC in the child also touches the whole inherited heap, so this
  probe moves page faults out of the tests as well as GC, and does not
  separate the two.

So of the 28 s of extra `test_run` in those rounds, about 12 s (40%) was GC
from the larger parent heap, which a pre-fork warm-up removes. The
remaining 17 s (60%) is tied to running methods compiled in the parent
rather than in the child. First-call writes
(inline caches) into the parent's instruction sequences, each copying a
shared page, would explain it, but that mechanism was not measured.

On top of that the parent spends 2.3 s building and evaluating the
meta-methods before the first mutation, serially. That time was not broken
down; it covers two extra `Prism.parse` calls per variant in the
local-conflict guard and compiling methods that hold a full copy of the
body per variant (1751 copies of a few long methods on i18n).

## Decision

**No-go**, and it still holds with the pre-fork warm-up measured above.
Four reasons:

1. **The ceiling is low.** What schemata removes is `apply`: 0.1% of
   killtime on the fixture, 3.6% on dry-monads `maybe.rb`, 20% on i18n.
   Three quarters of that 20% is one parse (below) that needs no schemata
   to remove.
2. **On the one target where the ceiling is worth having, it did not win.**
   As built (whole-body variants, no pre-fork GC) i18n ran 8% slower. A
   `Process.warmup` in the parent removes the GC part of that loss, but the
   same warm-up speeds up the eval path too, and against that schemata
   ties (killtime -1%, wall +3%): the tests still run 9 ms per
   mutant slower on parent-compiled methods, which eats the saved `apply`.
   dry-monads came out even. This is measured for this whole-body design
   only; switching at the mutated expression (Untch, Stryker) would cut
   the heap growth and build time, and was not built.
3. **The correctness surface is large for what is left.** Variant line
   numbers shift. Local variables leak between branches and need a parse per
   variant to guard. Visibility, `module_function` and aliases have to be
   re-applied by hand. Load-time captures of a method (`method(:x)`,
   `instance_method`, memoizers) diverge from the eval path silently.
   `define_method`, `def`s in blocks and endless `def`s are excluded or need
   rewriting. Verdicts were identical on 2888 mutants across three targets,
   but each of these is a way for a later target to disagree.
4. **It does not compose with what the eval path already has.** Neutralized
   class bodies, redeclared subjects (scope, aasm, callbacks, concern hooks)
   and `load_crashed` detection stay on the eval path. Schemata would be a
   second way to apply a mutation, to be kept equivalent with the first.

Reason 1 holds on its own: even a version that cost nothing could remove at
most a fifth of i18n's killtime, and three quarters of that a parse memo
removes without schemata. Reasons 3 and 4 hold for any version.
Expression-level switching was not built: it saves the same `apply`, keeps
reasons 1, 3 and 4, and whether it also avoids the slower tests of reason 2
is open.

## What to do instead

**Parse the original's constant names once, in the parent.**
`ConstantPinner#call(mutation.original_source)` runs `Prism.parse` on the
same unchanged source in every mutation process. Measured with the names
memoized per source and filled in `MutationExecutor#warm` (the same harness,
`EV_PIN_MEMO=1`), i18n alternated off/on, two runs each:

| | `apply` total | killtime | duration |
|---|---|---|---|
| off | 17.97 s, 17.58 s | 81.6 s, 79.4 s | 42.1 s, 41.1 s |
| on | 8.52 s, 8.77 s | 72.6 s, 75.6 s | 37.7 s, 39.2 s |

That is about **-8% killtime and -8% wall on i18n** (killtime 80.5 → 74.1 s,
wall 41.6 → 38.4 s, means of two runs), with verdicts identical
(1837/1837), using a cache filled in the parent the way the concern
registry already is. Of the 9.1 s of `apply` saved, about 6.4 s reaches
killtime: `test_run` rose with the memo on (45.4 / 43.9 → 46.2 / 48.6 s),
probably the same shift of GC work into the tests that schemata shows
(not measured for the memo). Two runs each is thin: unmodified i18n runs in
the same session ranged from 38.2 to 42.1 s, about the size of the gain. It
is a small change with no new way to apply a mutation. Worth filing as its
own issue, and the gain should be confirmed there with
`scripts/benchmark_perf` (interleaved repeats), which this spike did not
use. `RedefinitionRecovery` parses the original too, but only on a
conflict.

**Collect and compact the parent's heap once before forking.** In the
warm-up rounds above, `Process.warmup` in the parent after
`MutationExecutor#warm` cut the eval path's GC per mutation process from
12.2 to 6.9 ms and its `test_run` from 51.5 to 41.7 s: **-11% killtime and
-11% wall on i18n** (92.6 → 82.2 s, 48.0 → 42.9 s, means of three
alternated runs, verdicts identical). It is one call with no new way to
apply a mutation. Worth its own issue, measured there with
`scripts/benchmark_perf` on more than one canary (it compacts the heap,
which a C extension that does not support compaction could mind).

The rest of the per-mutant fixed cost is the isolation itself (fork, sandbox,
reap: 9.5–10.5 ms per mutant under `fork`, more than `apply` on every
target) and per-mutation framework reset inside `test_run`. Schemata touches
neither.

## Reproducing

The harness, the timing wrapper and the aggregation scripts are in
[`scripts/schemata_spike/`](../scripts/schemata_spike/); its README lists
every environment switch. Corpus: copies of the dry-monads and i18n canaries
(pinned commits in `scripts/benchmark_perf.yml`) and of the fixture, each
with a Gemfile adding `gem "evilution", path: <tree>`.

- Baseline: the per-mutation `timings` (`apply`, `test_run`,
  `confirmation`) of a normal JSON run. Isolation overhead per mutant is
  `duration` minus those.
- Step breakdown (`apply_prof.rb`): prepends a timing wrapper to `call` of
  `SyntaxValidator`, `ConstantPinner`, `ConcernStateCleaner`,
  `SourceEvaluator`, `RedefinitionRecovery` and
  `MutationApplier#mark_feature_loaded`, loaded with `RUBYOPT=-r<file>` (it
  must `require "bundler/setup"` first).
- Schemata (`schemata.rb`): the harness described under
  [Prototype](#prototype): a module
  prepended to `MutationExecutor` whose private `warm(integration,
  mutations)` calls `super` and then builds and evaluates the meta-methods,
  and one prepended to `MutationApplier` whose `call`/`restore`
  set and clear the global for the mutations it switched (keyed by file and
  `mutated_source.hash`, stable across `fork`).
- Probes and the memo: switches of the same harness (`EV_SCHEMATA_REEVAL`,
  `EV_SCHEMATA_GC`, `EV_PARENT_WARMUP`, `EV_GCSTAT`, `EV_PIN_MEMO`).
- Verdict equivalence (`compare_verdicts.rb`): match the two runs' JSON
  entries by file, line, operator and diff, and compare statuses.

Commands (in the target dir, `--jobs 2`):

```
# fixture
bundle exec evilution run lib/pricing.rb lib/inventory.rb lib/grade.rb --jobs 2 --format json
# dry-monads
bundle exec evilution run lib/dry/monads/maybe.rb --spec spec/unit/maybe_spec.rb \
  --integration rspec --preload spec/spec_helper.rb --jobs 2 --format json
# i18n
RUBYOPT=-Itest bundle exec evilution run lib/i18n/backend/base.rb --spec test/i18n_test.rb \
  --integration minitest --preload test/test_helper.rb --jobs 2 --format json
```
