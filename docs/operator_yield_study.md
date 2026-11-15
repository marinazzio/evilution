# Operator yield study

Status: **study, no code change.** The default profile stays as it is; a trim
is proposed for a later decision. Decision at the end.

## Question

1.5.0 added 19 operators and more mutants per existing operator (the
`integer_literal` width sentinel and `n - 1`, `float_literal` `NAN` /
`INFINITY`, `array_literal` / `hash_literal` delete-each, hash key rename,
`constant_namespace_strip`, `variable_read_to_nil`, ...). Which operators, or
variants of one, cost run time without adding information, and could move to
`strict` or to a `fast` profile?

"Information" is measured the way the mutation-analysis literature does:

- **Sufficient operator sets** (Offutt, Lee, Rothermel, Untch, Zapf, *An
  experimental determination of sufficient mutant operators*, TOSEM 1996): a
  test set that kills the mutants of a subset of the operators kills almost
  all mutants of the rest, so the rest add cost but little test-adequacy
  signal.
- **Subsumption / dominator mutants** (Ammann, Delamaro, Offutt, *Establishing
  theoretical minimal sets of mutants*, ICST 2014; Kurtz et al., *Mutant
  subsumption graphs*, 2014): mutant A subsumes mutant B when A is killed by
  at least one test and every test that kills A also kills B. B is then
  redundant: any test set that kills A kills B. Kill sets measured on a real
  test suite give the *dynamic* version of the relation, which is what is
  measured here.

## Method

Evilution tree: 1.5.1 plus 44 unreleased commits (commit `0d55d97`; the new
options among them, `--probe-first` and `skip_sites`, are off by default and
were not used), `--jobs 2` (Redmine `--jobs 1`), one file per run, on copies
of the `scripts/benchmark_perf.yml` corpus. 8 targets: 3 fixture files and 5
real projects.

| Target | File | Tests | Mutants |
| --- | --- | --- | ---: |
| fixture (3 targets) | `lib/pricing.rb`, `lib/inventory.rb`, `lib/grade.rb` | `spec/*_spec.rb` (RSpec) | 440 |
| dry-monads | `lib/dry/monads/maybe.rb` | `spec/unit/maybe_spec.rb` (RSpec) | 611 |
| httparty | `lib/httparty.rb` | `spec/httparty_spec.rb` (RSpec), fixture path made absolute | 1412 |
| grape | `lib/grape/declared_params_handler.rb` | `spec/grape/endpoint/declared_spec.rb` (RSpec) | 693 |
| i18n | `lib/i18n/backend/base.rb` | `test/i18n_test.rb` (Minitest) | 1837 |
| redmine | `app/models/tracker.rb` | `test/unit/tracker_test.rb` (Minitest, Rails) | 500 |
| **total** | | | **5493** |

The two known corpus artifacts are avoided as in the
[probe-first spike](probe_first_spike.md): httparty runs with
`spec/httparty_spec.rb:226` opening its fixture by an absolute path (with the
cwd-relative one every mutant is a fake kill), and dry-monads uses `maybe.rb`
instead of `list.rb` (whose class body cannot be re-evaluated, so every mutant
is killed).

Three runs per target:

1. **Default run** (`stop_on_kill` on, as users run it): verdicts and each
   mutant's `duration`. Time share is the operator's share of the summed
   durations (killtime).
2. **Kill-set run**: `--no-stop-on-kill`, so every selected example runs, with
   a measurement-only hook (see [Reproducing](#reproducing)) that records the
   ids of **all** failing examples per mutant. The JSON report names only the
   first killer (`killing_test`), which is not enough for subsumption.
3. **Generation dump**: every mutation the operators generate, before the
   planner removes duplicates. Two operators often generate the same code;
   the planner keeps one mutant and reports it under the operator registered
   first. Dropping that operator does not remove the mutant: it comes back
   under the next operator that generates it, with the same verdict. The
   dump says which mutants come back.

Verdicts agreed between the two test runs for every mutant on every target. 58
kills (dry-monads 11, httparty 32, redmine 15) have no failing example: the
mutated file failed to load (a class-body or `def`-line mutation that raises
when the file is evaluated). They count as killed but cannot be shown
subsumed, so they are always counted as information lost when dropped.

**Test scope.** Each target runs one test file, and evilution's default
lexical example targeting narrows it further to the examples that mention the
mutated method. Subsumption is measured against that pool. With a small pool
many mutants share the same few killing examples, so dynamic subsumption
over-approximates true subsumption: a fuller suite can tell apart mutants
that look redundant here. i18n is the extreme case: 1499 of its 1837 mutants
survive (18% score), so its kill data is thin.

Definitions:

- **Kill rate**: (killed + timed out) / (killed + survived + timed out).
- **Subsumed share**: among the operator's killed mutants with a kill set, the
  share that is not a dominator. A *site* (same line, or same subject =
  method) is partitioned by kill set; a kill-set class with no proper subset
  among the site's classes is minimal, and its members share one dominator
  credit (so three identical minimal mutants are 1/3 dominator each,
  2/3 subsumed). Line-level compares the mutants of one line; subject-level is
  the wider and still sound comparison (all mutants of one method run the same
  selected examples, so their kill sets are comparable).
- **Drop cost** of a set of operators/variants, per target. A mutant of the
  set is **removed** unless a kept operator generates the same code; then it
  **returns** under that operator and costs nothing. Of the removed mutants,
  the cost is the killed ones for which **no kept mutant of the same subject**
  has a non-empty kill set contained in theirs ("lost kills": these are the
  kills whose test requirement nothing else carries), timeouts and load-time
  kills (never subsumed), and the **survivor lines lost** (lines where a
  removed mutant survived and no kept mutant survives). Survivors have no kill
  set, so their redundancy cannot be measured from test results; a survivor
  on a line where another kept mutant also survives points the reader at the
  same gap, one that is alone on its line does not.

## Results per operator

All targets together, sorted by killtime. 106 of the 155 default operators
fired on the corpus.

| operator | mutants | share | killtime s | time share | killed | survived | timed out | other | kill rate | subsumed (line) | subsumed (subject) |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| method_call_removal | 393 | 7.2% | 60.8 | 7.4% | 235 | 158 | 0 | 0 | 59.8% | 82.4% | 91.0% |
| integer_literal | 170 | 3.1% | 51.6 | 6.3% | 105 | 65 | 0 | 0 | 61.8% | 75.0% | 82.4% |
| method_body_replacement | 310 | 5.6% | 46.3 | 5.7% | 217 | 91 | 0 | 2 | 70.5% | 71.3% | 94.9% |
| string_literal | 174 | 3.2% | 38.6 | 4.7% | 91 | 83 | 0 | 0 | 52.3% | 86.4% | 95.3% |
| symbol_literal | 328 | 6.0% | 38.3 | 4.7% | 160 | 168 | 0 | 0 | 48.8% | 85.1% | 92.8% |
| argument_nil_substitution | 302 | 5.5% | 36.7 | 4.5% | 152 | 149 | 0 | 1 | 50.5% | 86.6% | 91.7% |
| argument_list_removal | 261 | 4.8% | 35.1 | 4.3% | 151 | 110 | 0 | 0 | 57.9% | 92.0% | 96.4% |
| call_to_nil | 241 | 4.4% | 33.2 | 4.1% | 151 | 90 | 0 | 0 | 62.7% | 84.8% | 94.2% |
| statement_deletion | 197 | 3.6% | 28.2 | 3.4% | 124 | 73 | 0 | 0 | 62.9% | 84.2% | 91.9% |
| argument_removal | 217 | 4.0% | 27.5 | 3.4% | 115 | 102 | 0 | 0 | 53.0% | 89.8% | 93.7% |
| conditional_negation | 200 | 3.6% | 27.3 | 3.3% | 117 | 83 | 0 | 0 | 58.5% | 79.8% | 93.9% |
| method_body_to_raise | 153 | 2.8% | 22.6 | 2.8% | 113 | 39 | 0 | 1 | 74.3% | 85.8% | 95.5% |
| argument_propagation | 129 | 2.3% | 19.0 | 2.3% | 72 | 57 | 0 | 0 | 55.8% | 83.6% | 90.6% |
| send_mutation | 76 | 1.4% | 18.1 | 2.2% | 19 | 54 | 0 | 3 | 26.0% | 90.1% | 93.8% |
| nil_replacement | 76 | 1.4% | 17.6 | 2.2% | 44 | 32 | 0 | 0 | 57.9% | 83.8% | 91.4% |
| conditional_branch | 110 | 2.0% | 16.9 | 2.1% | 66 | 44 | 0 | 0 | 60.0% | 81.0% | 93.8% |
| argument_order_permutation | 122 | 2.2% | 14.6 | 1.8% | 58 | 64 | 0 | 0 | 47.5% | 88.9% | 92.4% |
| negation_insertion | 100 | 1.8% | 13.4 | 1.6% | 70 | 30 | 0 | 0 | 70.0% | 95.7% | 98.9% |
| variable_read_to_nil | 124 | 2.3% | 13.2 | 1.6% | 59 | 65 | 0 | 0 | 47.6% | 75.5% | 93.1% |
| boolean_operand_promotion | 88 | 1.6% | 11.5 | 1.4% | 55 | 33 | 0 | 0 | 62.5% | 69.3% | 83.2% |
| conditional_flip | 85 | 1.5% | 11.3 | 1.4% | 60 | 25 | 0 | 0 | 70.6% | 93.7% | 99.1% |
| predicate_replacement | 88 | 1.6% | 10.7 | 1.3% | 61 | 27 | 0 | 0 | 69.3% | 83.8% | 88.0% |
| comparison_replacement | 68 | 1.2% | 10.3 | 1.3% | 45 | 23 | 0 | 0 | 66.2% | 82.3% | 86.0% |
| method_body_to_super | 60 | 1.1% | 9.4 | 1.2% | 37 | 23 | 0 | 0 | 61.7% | 76.0% | 85.3% |
| array_literal | 46 | 0.8% | 9.3 | 1.1% | 14 | 32 | 0 | 0 | 30.4% | 88.9% | 93.1% |
| bang_method | 51 | 0.9% | 8.7 | 1.1% | 14 | 37 | 0 | 0 | 27.5% | 70.8% | 81.4% |
| argument_method_call_replacement | 62 | 1.1% | 8.5 | 1.0% | 22 | 40 | 0 | 0 | 35.5% | 92.7% | 97.3% |
| keyword_argument_removal | 70 | 1.3% | 8.0 | 1.0% | 36 | 34 | 0 | 0 | 51.4% | 66.2% | 99.0% |
| optional_parameter_to_required | 55 | 1.0% | 7.5 | 0.9% | 26 | 28 | 0 | 1 | 48.1% | 62.7% | 74.0% |
| optional_default_injection | 52 | 0.9% | 7.4 | 0.9% | 33 | 19 | 0 | 0 | 63.5% | 27.1% | 73.8% |
| boolean_literal_replacement | 64 | 1.2% | 7.2 | 0.9% | 16 | 48 | 0 | 0 | 25.0% | 74.5% | 86.3% |
| short_circuit_to_eager | 44 | 0.8% | 6.9 | 0.8% | 15 | 29 | 0 | 0 | 34.1% | 96.7% | 98.3% |
| collection_replacement | 37 | 0.7% | 6.7 | 0.8% | 28 | 7 | 0 | 2 | 80.0% | 88.4% | 94.8% |
| block_pass_removal | 26 | 0.5% | 5.8 | 0.7% | 5 | 21 | 0 | 0 | 19.2% | 36.5% | 37.2% |
| range_replacement | 5 | 0.1% | 5.8 | 0.7% | 0 | 5 | 0 | 0 | 0.0% | – | – |
| local_variable_assignment | 53 | 1.0% | 5.7 | 0.7% | 32 | 21 | 0 | 0 | 60.4% | 93.6% | 98.6% |
| constant_namespace_strip | 42 | 0.8% | 5.5 | 0.7% | 24 | 17 | 0 | 1 | 58.5% | 89.4% | 94.2% |
| keyword_value_swap | 39 | 0.7% | 5.5 | 0.7% | 26 | 13 | 0 | 0 | 66.7% | 71.8% | 83.1% |
| boolean_operator_replacement | 44 | 0.8% | 5.4 | 0.7% | 34 | 10 | 0 | 0 | 77.3% | 92.8% | 96.1% |
| boolean_expression_to_nil | 43 | 0.8% | 5.2 | 0.6% | 32 | 11 | 0 | 0 | 74.4% | 95.3% | 98.0% |
| index_write_to_value | 35 | 0.6% | 4.9 | 0.6% | 27 | 8 | 0 | 0 | 77.1% | 89.0% | 93.1% |
| compound_assignment | 20 | 0.4% | 4.7 | 0.6% | 17 | 3 | 0 | 0 | 85.0% | 79.7% | 98.1% |
| block_param_removal | 27 | 0.5% | 4.6 | 0.6% | 17 | 10 | 0 | 0 | 63.0% | 79.5% | 94.2% |
| index_assignment_removal | 26 | 0.5% | 3.8 | 0.5% | 19 | 7 | 0 | 0 | 73.1% | 88.3% | 93.5% |
| if_branch_swap | 22 | 0.4% | 3.7 | 0.4% | 17 | 5 | 0 | 0 | 77.3% | 93.6% | 98.1% |
| return_value_removal | 20 | 0.4% | 3.5 | 0.4% | 12 | 8 | 0 | 0 | 60.0% | 86.0% | 87.4% |
| instance_variable_write | 19 | 0.3% | 3.4 | 0.4% | 12 | 6 | 0 | 1 | 66.7% | 64.3% | 82.1% |
| index_to_fetch | 32 | 0.6% | 3.0 | 0.4% | 14 | 15 | 0 | 3 | 48.3% | 58.9% | 92.9% |
| block_removal | 21 | 0.4% | 2.9 | 0.3% | 12 | 9 | 0 | 0 | 57.1% | 95.1% | 98.6% |
| index_receiver_to_self | 32 | 0.6% | 2.8 | 0.3% | 21 | 11 | 0 | 0 | 65.6% | 93.9% | 99.0% |
| block_body_to_raise | 21 | 0.4% | 2.8 | 0.3% | 12 | 9 | 0 | 0 | 57.1% | 95.8% | 99.8% |
| attribute_write_to_read | 20 | 0.4% | 2.7 | 0.3% | 16 | 4 | 0 | 0 | 80.0% | 86.9% | 92.8% |
| keyword_argument | 12 | 0.2% | 2.7 | 0.3% | 8 | 4 | 0 | 0 | 66.7% | 92.9% | 100.0% |
| index_to_key_predicate | 30 | 0.5% | 2.6 | 0.3% | 14 | 16 | 0 | 0 | 46.7% | 89.5% | 91.6% |
| splat_operator | 16 | 0.3% | 2.4 | 0.3% | 3 | 13 | 0 | 0 | 18.8% | 50.0% | 54.2% |
| binary_operand_promotion | 13 | 0.2% | 2.3 | 0.3% | 13 | 0 | 0 | 0 | 100.0% | 77.5% | 86.6% |
| arithmetic_replacement | 13 | 0.2% | 2.2 | 0.3% | 12 | 1 | 0 | 0 | 92.3% | 86.4% | 91.8% |
| receiver_replacement | 5 | 0.1% | 2.2 | 0.3% | 4 | 1 | 0 | 0 | 80.0% | 79.5% | 85.2% |
| string_interpolation | 16 | 0.3% | 2.1 | 0.3% | 8 | 8 | 0 | 0 | 50.0% | 91.3% | 97.3% |
| return_keyword_removal | 17 | 0.3% | 2.0 | 0.2% | 12 | 5 | 0 | 0 | 70.6% | 89.1% | 92.1% |
| coercion_emptying | 8 | 0.1% | 1.9 | 0.2% | 5 | 3 | 0 | 0 | 62.5% | 87.3% | 89.8% |
| visibility_removal | 5 | 0.1% | 1.8 | 0.2% | 0 | 5 | 0 | 0 | 0.0% | – | – |
| block_body_to_nil | 10 | 0.2% | 1.8 | 0.2% | 7 | 3 | 0 | 0 | 70.0% | 50.0% | 83.3% |
| case_when | 43 | 0.8% | 1.8 | 0.2% | 7 | 36 | 0 | 0 | 16.3% | 66.7% | 98.6% |
| constant_read_to_nil | 25 | 0.5% | 1.7 | 0.2% | 5 | 20 | 0 | 0 | 20.0% | 62.3% | 72.2% |
| memoization_break | 5 | 0.1% | 1.7 | 0.2% | 0 | 5 | 0 | 0 | 0.0% | – | – |
| forwarded_argument_drop | 9 | 0.2% | 1.5 | 0.2% | 5 | 4 | 0 | 0 | 55.6% | 17.8% | 37.8% |
| mixin_removal | 9 | 0.2% | 1.4 | 0.2% | 0 | 9 | 0 | 0 | 0.0% | – | – |
| hash_literal | 12 | 0.2% | 1.4 | 0.2% | 12 | 0 | 0 | 0 | 100.0% | 92.3% | 93.8% |
| freeze_removal | 3 | 0.1% | 1.4 | 0.2% | 0 | 3 | 0 | 0 | 0.0% | – | – |
| regexp_mutation | 10 | 0.2% | 1.3 | 0.2% | 6 | 4 | 0 | 0 | 60.0% | 88.3% | 96.7% |
| superclass_removal | 9 | 0.2% | 1.3 | 0.2% | 0 | 9 | 0 | 0 | 0.0% | – | – |
| block_parameter_drop | 9 | 0.2% | 1.2 | 0.2% | 3 | 6 | 0 | 0 | 33.3% | 98.0% | 98.0% |
| constant_write_to_nil | 8 | 0.1% | 1.1 | 0.1% | 4 | 4 | 0 | 0 | 50.0% | 0.0% | 0.0% |
| index_to_at | 14 | 0.3% | 1.1 | 0.1% | 4 | 10 | 0 | 0 | 28.6% | 100.0% | 100.0% |
| integer_division_to_fdiv | 1 | 0.0% | 1.0 | 0.1% | 0 | 1 | 0 | 0 | 0.0% | – | – |
| alias_removal | 8 | 0.1% | 1.0 | 0.1% | 0 | 8 | 0 | 0 | 0.0% | – | – |
| block_body_promotion | 4 | 0.1% | 0.9 | 0.1% | 3 | 1 | 0 | 0 | 75.0% | 72.2% | 83.3% |
| equality_to_identity | 8 | 0.1% | 0.9 | 0.1% | 2 | 6 | 0 | 0 | 25.0% | 94.3% | 94.3% |
| yield_statement | 7 | 0.1% | 0.9 | 0.1% | 5 | 2 | 0 | 0 | 71.4% | 66.7% | 76.7% |
| regex_simplification | 4 | 0.1% | 0.7 | 0.1% | 2 | 2 | 0 | 0 | 50.0% | 0.0% | 50.0% |
| float_literal | 10 | 0.2% | 0.7 | 0.1% | 10 | 0 | 0 | 0 | 100.0% | 90.0% | 90.0% |
| attr_accessor_swap | 4 | 0.1% | 0.7 | 0.1% | 0 | 4 | 0 | 0 | 0.0% | – | – |
| regexp_anchor_promotion | 3 | 0.1% | 0.6 | 0.1% | 0 | 3 | 0 | 0 | 0.0% | – | – |
| dynamic_dispatch_resolution | 3 | 0.1% | 0.6 | 0.1% | 0 | 3 | 0 | 0 | 0.0% | – | – |
| comparison_operand_swap | 1 | 0.0% | 0.4 | 0.1% | 1 | 0 | 0 | 0 | 100.0% | 100.0% | 100.0% |
| regexp_anchor_to_predicate | 2 | 0.0% | 0.4 | 0.0% | 0 | 2 | 0 | 0 | 0.0% | – | – |
| block_destructuring_expansion | 3 | 0.1% | 0.3 | 0.0% | 2 | 1 | 0 | 0 | 66.7% | 83.3% | 100.0% |
| symbol_to_proc_replacement | 2 | 0.0% | 0.3 | 0.0% | 2 | 0 | 0 | 0 | 100.0% | 100.0% | 100.0% |
| explicit_super_mutation | 2 | 0.0% | 0.3 | 0.0% | 1 | 0 | 0 | 1 | 100.0% | 0.0% | 87.5% |
| dig_to_fetch_chain | 1 | 0.0% | 0.2 | 0.0% | 0 | 1 | 0 | 0 | 0.0% | – | – |
| rescue_body_replacement | 6 | 0.1% | 0.2 | 0.0% | 0 | 6 | 0 | 0 | 0.0% | – | – |
| index_range_to_drop | 1 | 0.0% | 0.2 | 0.0% | 0 | 1 | 0 | 0 | 0.0% | – | – |
| next_statement | 1 | 0.0% | 0.2 | 0.0% | 0 | 1 | 0 | 0 | 0.0% | – | – |
| regexp_option_removal | 1 | 0.0% | 0.2 | 0.0% | 0 | 1 | 0 | 0 | 0.0% | – | – |
| double_negation_removal | 1 | 0.0% | 0.2 | 0.0% | 0 | 1 | 0 | 0 | 0.0% | – | – |
| forwarding_super_to_explicit | 1 | 0.0% | 0.2 | 0.0% | 1 | 0 | 0 | 0 | 100.0% | 0.0% | 75.0% |
| rescue_class_widening | 4 | 0.1% | 0.2 | 0.0% | 0 | 4 | 0 | 0 | 0.0% | – | – |
| regexp_character_type_complement | 1 | 0.0% | 0.1 | 0.0% | 1 | 0 | 0 | 0 | 100.0% | 100.0% | 100.0% |
| typed_default_return | 2 | 0.0% | 0.1 | 0.0% | 2 | 0 | 0 | 0 | 100.0% | 50.0% | 87.5% |
| rescue_removal | 3 | 0.1% | 0.1 | 0.0% | 0 | 3 | 0 | 0 | 0.0% | – | – |
| last_expression_removal | 2 | 0.0% | 0.1 | 0.0% | 1 | 1 | 0 | 0 | 50.0% | 66.7% | 66.7% |
| regex_capture | 2 | 0.0% | 0.1 | 0.0% | 0 | 2 | 0 | 0 | 0.0% | – | – |
| regexp_alternation_branch_deletion | 2 | 0.0% | 0.1 | 0.0% | 0 | 2 | 0 | 0 | 0.0% | – | – |
| regexp_capture_to_passive | 1 | 0.0% | 0.0 | 0.0% | 0 | 1 | 0 | 0 | 0.0% | – | – |
| collection_return | 1 | 0.0% | 0.0 | 0.0% | 0 | 1 | 0 | 0 | 0.0% | – | – |
| **total** | 5493 | 100% | 817.0 | 100% | 3095 | 2382 | 0 | 16 | 56.5% | 82.4% | 92.1% |

What the table says:

- **No operator dominates the cost.** The largest, `method_call_removal`, is
  7.4% of killtime; the top ten together are 48%. Cost follows volume: per
  mutant every operator costs about the same, since a mutant's time is mostly
  the selected examples' time.
- **Redundancy is everywhere, not in a few operators.** 82% of kills are
  subsumed at line level and 92% at subject level, with almost every operator
  between 80% and 99%. This matches the literature (most mutants are
  redundant; the minimal set is small), and it is a property of the test
  pool (a few examples kill most mutants of a method) at least as much as of
  the operators. With one test file per target, narrowed by example
  targeting (see *Test scope* above), these shares are upper bounds: a full
  suite could make some "subsumed" mutants distinguishing.
- **The 1.5.0 additions are not the cost.** 14 of the 19 operators added in
  1.5.0 fired on the corpus (`variable_read_to_nil`, `short_circuit_to_eager`,
  `constant_namespace_strip`, `index_write_to_value`, `index_receiver_to_self`,
  `index_to_key_predicate`, `constant_read_to_nil`, `constant_write_to_nil`,
  `memoization_break`, `visibility_removal`, `attr_accessor_swap`,
  `freeze_removal`, `rescue_class_widening`, `index_range_to_drop`); together
  they produce 362 mutants (6.6%) and 5.5% of killtime. `complex_literal`,
  `rational_literal`, `operator_write_receiver_promotion`, `sleep_to_zero`
  and `round_half_mode_swap` did not fire. The whole `array_literal` and
  `hash_literal` operators, delete-each included, are 1.1% and 0.2% of
  killtime.
- **Least subsumed, most informative**: `block_pass_removal` (37%),
  `optional_default_injection` (74% subject / 27% line),
  `optional_parameter_to_required`, `forwarded_argument_drop`, and the
  `integer_literal` neighbours `n + 1` / `n - 1` (below). These carry
  requirements no other operator generates.
- **Most subsumed** (>= 98% at subject level, operators with >= 20 mutants):
  `block_body_to_raise`, `conditional_flip`, `keyword_argument_removal`,
  `index_receiver_to_self`, `negation_insertion`, `local_variable_assignment`,
  `case_when`, `block_removal`, `short_circuit_to_eager`,
  `compound_assignment`, `if_branch_swap`, `boolean_expression_to_nil`.

### Variants

**`integer_literal` by variant**

| variant | mutants | share | killtime s | time share | killed | survived | timed out | other | kill rate | subsumed (line) | subsumed (subject) |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| width_sentinel | 41 | 24.1% | 13.8 | 26.6% | 24 | 17 | 0 | 0 | 58.5% | 82.5% | 90.2% |
| nil | 41 | 24.1% | 10.5 | 20.4% | 27 | 14 | 0 | 0 | 65.9% | 96.2% | 98.0% |
| succ | 18 | 10.6% | 8.5 | 16.4% | 10 | 8 | 0 | 0 | 55.6% | 37.7% | 42.0% |
| from_zero(+1/-1) | 24 | 14.1% | 7.7 | 14.9% | 8 | 16 | 0 | 0 | 33.3% | 80.8% | 85.2% |
| zero | 29 | 17.1% | 6.2 | 12.1% | 24 | 5 | 0 | 0 | 82.8% | 86.5% | 89.4% |
| pred | 17 | 10.0% | 4.9 | 9.6% | 12 | 5 | 0 | 0 | 70.6% | 19.9% | 51.9% |
| **total** | 170 | 100% | 51.6 | 100% | 105 | 65 | 0 | 0 | 61.8% | 75.0% | 82.4% |

The width sentinel is counted before the steps from zero: a `0` literal gets
`1`, `-1` and the sentinel `167`.

**`string_literal` by variant**

| variant | mutants | share | killtime s | time share | killed | survived | timed out | other | kill rate | subsumed (line) | subsumed (subject) |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| nil | 86 | 49.4% | 18.9 | 48.9% | 45 | 41 | 0 | 0 | 52.3% | 88.0% | 95.6% |
| empty | 58 | 33.3% | 13.0 | 33.6% | 24 | 34 | 0 | 0 | 41.4% | 88.8% | 95.9% |
| other | 30 | 17.2% | 6.8 | 17.5% | 22 | 8 | 0 | 0 | 73.3% | 80.6% | 94.3% |
| **total** | 174 | 100% | 38.6 | 100% | 91 | 83 | 0 | 0 | 52.3% | 86.4% | 95.3% |

`float_literal` produced 10 mutants on the corpus (fixture only; `NAN` 2,
`INFINITY` 4), all killed and all subsumed but one: too few to judge, and too
few to matter for cost.

- `n - 1` is 20% subsumed at line level and `n + 1` 38%, among the least
  redundant mutants in the corpus (with `forwarded_argument_drop` and
  `optional_default_injection`); dropping `n - 1` alone loses 8 kills nothing
  else carries, `n + 1` 5. Keep both.
- The `nil` replacement of a literal is 96-98% subsumed for integers and
  88-96% for strings: replacing an operand with `nil` raises on the first use,
  so any test that executes the line kills it, and the line's other mutants
  are killed by a subset of the same tests. It is also largely a duplicate:
  when the literal is a call argument, `argument_nil_substitution` generates
  the same `nil`, so dropping the `nil` variants of `integer_literal`,
  `string_literal` and `float_literal` removes only 64 of their 129 mutants
  (1.2% of mutants, 2.2% of killtime). It loses no kill with a failing example
  (2 load-time kills on Redmine) and no survivor line.
- The `integer_literal` width sentinel (new in 1.5.0) is 41 mutants (0.7%),
  83-90% subsumed; dropping it alone loses 1 kill (a default argument
  `count = 1` on the fixture whose sentinel only one example notices). Not
  worth a change either way.

## Dropping operators

### One at a time

Dropping any single operator loses almost nothing: for nearly every operator,
each kill is subsumed by a kept mutant of the same method, and almost every
survivor shares its line with a kept survivor. "Generated" counts the
operator's mutants in the default run; "returned" the ones another operator
generates too, which stay in the run after the drop. Selected rows (all
targets, by killtime removed):

| operator | generated | removed | returned | killtime s | time share | kills | lost kills | survivors | survivor lines lost |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| method_call_removal | 393 | 372 | 21 | 58.1 | 7.1% | 221 | 8 | 151 | 4 |
| integer_literal | 170 | 151 | 19 | 48.8 | 6.0% | 95 | 20 | 56 | 2 |
| method_body_replacement | 310 | 231 | 79 | 34.0 | 4.2% | 166 | 0 | 63 | 3 |
| symbol_literal | 328 | 258 | 70 | 30.9 | 3.8% | 121 | 13 | 137 | 0 |
| string_literal | 174 | 130 | 44 | 29.8 | 3.7% | 64 | 0 | 66 | 1 |
| statement_deletion | 197 | 197 | 0 | 28.2 | 3.4% | 124 | 5 | 73 | 2 |
| integer_literal:width_sentinel | 41 | 41 | 0 | 13.8 | 1.7% | 24 | 1 | 17 | 0 |
| negation_insertion | 100 | 100 | 0 | 13.4 | 1.6% | 70 | 0 | 30 | 0 |
| variable_read_to_nil | 124 | 124 | 0 | 13.2 | 1.6% | 59 | 0 | 65 | 5 |
| string_literal:empty | 58 | 58 | 0 | 13.0 | 1.6% | 24 | 0 | 34 | 0 |
| conditional_flip | 85 | 85 | 0 | 11.3 | 1.4% | 60 | 0 | 25 | 0 |
| predicate_replacement | 88 | 88 | 0 | 10.7 | 1.3% | 61 | 0 | 27 | 0 |
| string_literal:nil | 86 | 42 | 44 | 10.1 | 1.2% | 18 | 0 | 24 | 0 |
| conditional_negation | 200 | 88 | 112 | 9.4 | 1.2% | 57 | 0 | 31 | 0 |
| integer_literal:succ | 18 | 18 | 0 | 8.5 | 1.0% | 10 | 5 | 8 | 0 |
| keyword_argument_removal | 70 | 70 | 0 | 8.0 | 1.0% | 36 | 2 | 34 | 0 |
| integer_literal:nil | 41 | 22 | 19 | 7.7 | 0.9% | 17 | 2 | 5 | 0 |
| integer_literal:from_zero(+1/-1) | 24 | 24 | 0 | 7.7 | 0.9% | 8 | 1 | 16 | 0 |
| optional_default_injection | 52 | 52 | 0 | 7.4 | 0.9% | 33 | 6 | 19 | 1 |
| collection_replacement | 37 | 37 | 0 | 6.7 | 0.8% | 28 | 0 | 7 | 0 |
| integer_literal:zero | 29 | 29 | 0 | 6.2 | 0.8% | 24 | 1 | 5 | 0 |
| block_pass_removal | 26 | 26 | 0 | 5.8 | 0.7% | 5 | 3 | 21 | 2 |
| conditional_branch | 110 | 44 | 66 | 5.7 | 0.7% | 27 | 0 | 17 | 0 |
| constant_namespace_strip | 42 | 42 | 0 | 5.5 | 0.7% | 24 | 0 | 17 | 0 |
| boolean_operator_replacement | 44 | 44 | 0 | 5.4 | 0.7% | 34 | 0 | 10 | 0 |
| integer_literal:pred | 17 | 17 | 0 | 4.9 | 0.6% | 12 | 8 | 5 | 0 |
| boolean_expression_to_nil | 43 | 38 | 5 | 4.5 | 0.6% | 27 | 0 | 11 | 0 |
| float_literal:infinity | 4 | 4 | 0 | 0.3 | 0.0% | 4 | 0 | 0 | 0 |
| float_literal:nan | 2 | 2 | 0 | 0.1 | 0.0% | 2 | 0 | 0 | 0 |
| argument_method_call_replacement | 62 | 0 | 62 | 0.0 | 0.0% | 0 | 0 | 0 | 0 |

`argument_method_call_replacement` (`foo(bar.baz)` -> `foo(bar)`) is a pure
duplicate on this corpus: `method_call_removal` generates every one of its 62
mutants, so dropping it changes nothing. `conditional_negation` replaces an
`if` / `unless` condition with `true` and `false`; when the condition is a
`?` call, `predicate_replacement` generates the same code, so 112 of its 200
mutants stay when it alone is dropped.

### Together: redundancy is mutual

Single-operator redundancy does not add up. Operators subsume each other, so
the set of "redundant on its own" operators is not redundant as a set. A
leave-one-target-out check shows it: on the five projects other than Redmine
(the three fixture files are one project), hold one out; on the other four
pick every operator or literal variant that removes >= 20 mutants and whose
drop-alone cost is 0 lost kills and 0 survivor lines lost; then drop the
picked set together on the held-out project:

| held out | picked | removed on held-out | time share | kills | lost kills | survivors | survivor lines lost |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| fixture | 18 | 161 / 440 | 50.6% | 136 | 38 | 25 | 2 |
| dry-monads | 19 | 161 / 611 | 26.7% | 113 | 3 | 47 | 1 |
| httparty | 19 | 472 / 1412 | 32.3% | 365 | 24 | 107 | 3 |
| grape | 18 | 189 / 693 | 26.8% | 177 | 0 | 11 | 0 |
| i18n | 16 | 410 / 1837 | 22.0% | 93 | 0 | 316 | 9 |

The greedy pick loses 38 real kills on the fixture and 24 on httparty that
the training projects said were free. A trim has to be chosen as a set and
validated as a set.

### Proposed trim

**Set B** is what the rule above picks in **every** fold of that table (an
operator pick covering its variants), with no hand edit. It is derived from
the five projects' data only; Redmine's data is not used, so Redmine is the
held-out check:

- `negation_insertion` (prefixes `!` to a `?` method call, `x.empty?` ->
  `!x.empty?`);
- `conditional_flip` (turns `if` into `unless` and back);
- `conditional_negation` (replaces an `if` / `unless` condition with `true`
  and with `false`);
- `predicate_replacement` (replaces a `?` method call with `true` and with
  `false`);
- `conditional_branch` (replaces the body of one branch of an `if` / `unless`
  with `nil`);
- `boolean_operator_replacement` (`&&` <-> `||`);
- `keyword_argument_removal` (drops one `key: value` argument from a call);
- the `""` variant of `string_literal` (the operator name and its other
  variants stay).

None of these is dropped because of what it emits: each is in the set because
its mutants were measured redundant (subsumed by a kept mutant of the same
method, or generated by a kept operator too) on every fold. For
`boolean_operator_replacement` the measurement agrees with the logic-mutant
subsumption hierarchy, which predicts the connector mutants are subsumed by
operand mutants such as `boolean_operand_promotion`'s `a && b` -> `a` / `b`
(Kaminski, Ammann, Offutt, *Better predicate testing*, AST 2011).

Dropped jointly on all 8 targets, set B removes 689 mutants (12.5%) and
11.6% of killtime, and loses 3 kills: 2 Redmine load-time crashes (below) and
1 httparty kill with a failing example, `parser(Parser) if true`
(`httparty.rb:281`, `conditional_negation`), that no kept mutant of
`HTTParty::ClassMethods#format` carries once all the condition operators go
together. Set B also removes every mutant that replaces an `if` condition with
`true` or `false`.

**Set B'** = set B without `conditional_negation`, the one member whose joint
drop loses a kill on a training project. Simulated on the default runs (each
removed mutant's measured duration taken out; mutants another operator
generates stay):

| target | mutants | removed | returned | killtime s | time share | kills | lost kills | survivors | survivor lines lost | score before | score after |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| fx-pricing | 135 | 2 | 2 | 0.1 | 0.5% | 2 | 0 | 0 | 0 | 90.4% | 90.2% |
| fx-inventory | 177 | 5 | 3 | 0.3 | 1.4% | 5 | 0 | 0 | 0 | 92.7% | 92.4% |
| fx-grade | 128 | 3 | 1 | 0.3 | 0.7% | 3 | 0 | 0 | 0 | 82.8% | 82.4% |
| dm-maybe | 611 | 39 | 16 | 5.9 | 6.9% | 32 | 0 | 7 | 0 | 66.3% | 65.2% |
| hp | 1412 | 68 | 11 | 10.8 | 4.9% | 63 | 0 | 5 | 0 | 71.9% | 70.8% |
| grape | 693 | 127 | 6 | 24.1 | 17.9% | 121 | 0 | 6 | 0 | 87.7% | 86.0% |
| i18n | 1837 | 201 | 17 | 7.9 | 10.9% | 56 | 0 | 145 | 0 | 18.1% | 16.9% |
| redmine | 500 | 44 | 10 | 18.0 | 8.2% | 30 | 2 | 14 | 0 | 70.1% | 70.3% |
| **total** | 5493 | 489 (8.9%) | 66 | 67.4 | 8.2% | 312 | 2 | 177 | 0 | | |

On every target, every kill set B' removes is subsumed by a kept mutant of the
same method, except 2 Redmine kills that are load-time crashes: dropping the
`:maximum` keyword from `validates_length_of :name, :maximum => ...` (and the
same for `:description`) raises when the model loads, which any test loading
the model notices. On Redmine, the held-out project, set B' loses no kill with
a failing example and no survivor line. (With Redmine in the training data
the folds no longer pick `keyword_argument_removal`: exactly the cost
Redmine shows.)

### Measured wall time

Set B' was measured by running the default set and set B' alternately on the
same tree (set B' removed through the same hook, `DROP_OPERATORS` /
`DROP_VARIANTS`), two repeats each, Redmine one, on six targets (the fixture
through `lib/grade.rb` only). The machine was shared with other jobs during
these runs, so wall times are noisy: repeats of the same run differ by up to
14% (httparty 116-132 s).

| target | mutants off | mutants on | Δ mutants | killtime off s | killtime on s | Δ killtime | wall off s (mean) | wall on s (mean) | Δ wall | killed mutants removed | score off | score on |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| fx-grade | 128 | 125 | -2.3% | 39.6 | 39.4 | -0.6% | 21.2 (20.4, 22.0) | 20.3 (20.2, 20.3) | -4.3% | 3 | 82.8% | 82.4% |
| dm-maybe | 611 | 572 | -6.4% | 122.0 | 108.4 | -11.2% | 57.8 (60.2, 55.4) | 49.2 (53.3, 45.1) | -14.8% | 41 | 66.3% | 65.2% |
| grape | 693 | 566 | -18.3% | 152.3 | 119.9 | -21.3% | 75.2 (75.4, 75.0) | 61.4 (59.2, 63.6) | -18.3% | 123 | 87.7% | 86.0% |
| i18n | 1837 | 1636 | -10.9% | 89.0 | 84.7 | -4.9% | 45.0 (45.3, 44.8) | 39.8 (42.3, 37.4) | -11.5% | 57 | 18.1% | 16.9% |
| hp | 1412 | 1344 | -4.8% | 269.3 | 270.7 | +0.5% | 124.0 (131.7, 116.3) | 119.2 (131.7, 106.7) | -3.9% | 66 | 71.9% | 70.8% |
| redmine | 500 | 456 | -8.8% | 245.4 | 210.9 | -14.1% | 239.1 | 204.0 | -14.7% | 35 | 70.1% | 70.3% |
| **total** | 5181 | 4699 | -9.3% | 917.7 | 833.8 | -9.1% | 562.3 | 493.9 | -12.2% | 325 | | |

"Killed mutants removed" counts killed mutants whose diff no longer appears
in the set-B' run (by file, line and diff, whatever operator reports it).

The mutant counts and scores match the simulation exactly on every target
(482 of 5181 mutants, 9.3%, over these six targets), because the simulation
lets a dropped mutant return when a kept operator generates the same code.
The returning ones, by file, line and diff between the two runs: of the 103
`conditional_branch` mutants in the default runs, 22 come back under
`call_to_nil` (a branch whose body is one call: replacing the body with `nil`
and the call with `nil` is the same code) and 9 under other operators; every
mutant of the other six operators and of the `""` variant is removed. (The
same holds for `argument_method_call_replacement`: in an A/B run that also
dropped it, all 60 of its mutants came back under `method_call_removal`.)

Measured, set B' removes **9.3% of mutants and 9.1% of killtime; wall time
falls 12% summed over the targets, from 4% (fixture, httparty) to 18%
(grape)**, against 8.7% of killtime simulated over the same targets. The
wall-time figures run ahead of killtime on dry-monads, i18n and Redmine, and
httparty's killtime does not move at all: that is the noise of the shared
machine, which two repeats (one on Redmine) cannot resolve. Mutant count and
killtime are the reliable figures: about 9% each. Mutation scores move by
-1.7 to +0.2 points.


## Decision

- **Default profile: no change now; set B' is the recommended trim, for the
  maintainer to decide.** The numbers for that call: set B' takes out 9% of
  mutants and 8% of killtime (simulated; measured on six targets: 9.3% of
  mutants, 9.1% of killtime, 12% of summed wall time), up to
  18% of killtime on a target heavy in conditions (grape). On 8 targets (3
  fixture files and 5 real projects) it loses no kill with a failing example
  that another mutant does not carry (2 load-time crash kills on Redmine) and
  no survivor line. Set B (the selection rule's output, which also drops
  `conditional_negation`) takes out 12.5% of mutants and 11.6% of killtime
  for 1 more lost kill on httparty, and leaves no operator that replaces an
  `if` condition with `true` / `false`. Before moving anything, re-run the
  kill-set measurement ([Reproducing](#reproducing)) on a wider corpus of real
  projects and fuller test suites: the set was validated on one held-out
  project, and subsumption measured on one test file per target is an upper
  bound.
- **Versioning.** `docs/versioning.md` names *adding* an operator to `default`
  a MINOR change; its MAJOR row covers "changing semantics", and it states
  that mutation score values are not contract, operator names are, and the
  exact mutated source an operator emits is not. Set B' has two parts that
  fall differently:
  - *Operator level* (`negation_insertion`, `conditional_flip`,
    `predicate_replacement`, `conditional_branch`,
    `boolean_operator_replacement`, `keyword_argument_removal`): moving them
    from `default` to `strict` keeps every operator name, but changes what
    `profile: default` means. By symmetry with the MINOR clause for adding
    one, removing one is plausibly MAJOR ("changing semantics"), unless the
    maintainer reads the profile's operator list as score-only (not
    contract), which would make it MINOR.
  - *Variant level* (the `""` replacement of `string_literal`): there is no
    mechanism for it today. Profiles select whole operator classes
    (`Mutator::Registry.for_profile`); the study removed the variant with a
    test hook filtering `Registry#mutations_for`. Two ways to ship it:
    delete the variant from `StringLiteral` outright (the operator name stays
    and only its emitted mutants change, which the policy treats as not
    contract: PATCH or MINOR), or keep it under `strict`, which needs either
    a new operator name for it (a contract addition: MINOR) or a per-profile
    operator option (new internal mechanism). The chosen mechanism decides the
    versioning question for this part.
- **`fast` profile: not shipped.** A saving of about 9% does not justify a new
  public profile name that must keep its meaning for the whole 1.x line. It
  is smaller than `skip_uncovered` / `--probe-first`, which remove mutants no
  test reaches (up to 48% of wall time on i18n, see the
  [probe-first spike](probe_first_spike.md)) instead of mutants a test does
  reach. If a wider corpus confirms set B', the cheaper route is the
  default-profile change above; a `fast` profile would only be worth it with
  a larger cut that accepts lost kills, which this data does not support.
- **Not proposed**: moving any 1.5.0 operator. They are 6.6% of mutants, and
  their subsumption is no higher than the old operators'. The
  `integer_literal` `n + 1` / `n - 1` neighbours are among the least
  redundant mutants in the corpus. Dropping `argument_method_call_replacement`
  or the `nil` replacement of literals is not proposed either: the first is a
  pure duplicate of `method_call_removal` here (dropping it changes nothing),
  the second mostly a duplicate of `argument_nil_substitution` (1.2% of
  mutants removed).
- **Noticed on the way, not changed**: `string_literal` turns a word of a
  `%w()` array into `""` and into `nil`, which inside `%w` are just two other
  words (`%w(a "" c)`, `%w(a nil c)`): two mutants with the same effect per
  word (Redmine `tracker.rb:28`, 12 mutants).

## Reproducing

The hook, the variant classifier, the run script and the analysis are in
[`scripts/operator_yield/`](../scripts/operator_yield/README.md)
(measurement-only: not loaded by the gem, not packaged with it). The README
there lists the corpus setup and the commands that produce every table
above.

- **Kill-set hook** (`killsets_hook.rb`), loaded with `bundle exec ruby
  -r<hook> exe/evilution run ...`. With `KILLSETS_OUT=<file.jsonl>` it
  prepends `run_tests(mutation)` on `Evilution::Integration::RSpec` and
  `::Minitest` (resets a per-run list, then writes one JSON line per
  mutation: file, line, operator, subject, diff, failing ids) and collects the
  failing ids in `RSpec#build_result`
  (`Integration::RSpec::ExampleIds.failed(::RSpec.world)`) and
  `Minitest#run_minitest` (its `failed_ids`); run it with
  `--no-stop-on-kill`. With `GENERATED_OUT=<file.jsonl>` it writes every
  mutation `MutationPlanner` generates before de-duplication, with a digest
  of the mutated file. With `DROP_OPERATORS=a,b` it removes operators from
  `Mutator::Registry.default`, and with `DROP_VARIANTS=op:variant,...` it
  filters the mutations `Registry#mutations_for` returns by the variant
  classifier.
- **Variant classifier** (`variants.rb`): the changed token of the diff's
  first `-`/`+` pair, widened to whole tokens; for `integer_literal` compared
  numerically (width sentinel first, then `zero`, `n + 1`, `n - 1`, `±1` from
  `0`; `nil`).
- **Analysis** (`analyze.rb`, `ab_compare.rb`): matches the default run, the
  kill-set records and the generation dump by file, line, operator and diff,
  then computes the tables above (subsumption with fractional dominator
  credit, drop cost with returning duplicates, leave-one-target-out).
