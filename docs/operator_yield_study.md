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
  subsumption graphs*, 2014): mutant A subsumes mutant B when every test that
  kills A also kills B. B is then redundant: any test set that kills A kills
  B. Kill sets measured on a real test suite give the *dynamic* version of the
  relation, which is what is measured here.

## Method

Evilution tree: this branch (with the epic's engine changes), `--jobs 2`
(Redmine `--jobs 1`), one file per run, on scratchpad copies of the
`scripts/benchmark_perf.yml` corpus:

| Target | File | Tests | Mutants |
| --- | --- | --- | ---: |
| fixture (3 runs) | `lib/pricing.rb`, `lib/inventory.rb`, `lib/grade.rb` | `spec/*_spec.rb` (RSpec) | 440 |
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

Two runs per target:

1. **Default run** (`stop_on_kill` on, as users run it): verdicts and each
   mutant's `duration`. Time share is the operator's share of the summed
   durations (killtime).
2. **Kill-set run**: `--no-stop-on-kill`, so every selected example runs, with
   a measurement-only hook (below) that records the ids of **all** failing
   examples per mutant. The JSON report names only the first killer
   (`killing_test`), which is not enough for subsumption.

Verdicts agreed between the two runs for every mutant on every target. 58
kills (dry-monads 11, httparty 32, redmine 15) have no failing example: the
mutated file failed to load (a class-body or `def`-line mutation that raises
when the file is evaluated). They count as killed but cannot be shown
subsumed, so they are always counted as information lost when dropped.

Definitions:

- **Kill rate**: (killed + timed out) / (killed + survived + timed out).
- **Subsumed share**: among the operator's killed mutants with a kill set, the
  share that is not a dominator. A *site* (same line, or same subject =
  method) is partitioned by kill set; a kill-set class with no proper subset
  among the site's classes is minimal, and its members share one dominator
  credit (so three identical minimal mutants are 1/3 dominator each,
  2/3 subsumed). Line-level is the issue's "same site"; subject-level is the
  wider and still sound comparison (all mutants of one method run the same
  selected examples, so their kill sets are comparable).
- **Drop cost** of a set of operators/variants, per target: the killed mutants
  of the set for which **no kept mutant of the same subject** has a non-empty
  kill set contained in theirs ("kills not subsumed": these are the kills
  whose test requirement nothing else carries), timeouts and load-time kills
  (never subsumed), and the **survivor lines lost** (lines where a dropped
  mutant survived and no kept mutant survives). Survivors have no kill set, so
  their redundancy cannot be measured from test results; a survivor on a line
  where another kept mutant also survives points the reader at the same gap,
  one that is alone on its line does not.

## Results per operator

All targets together, sorted by killtime. 107 of 155 default operators fired
on the corpus.

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
  suite (a few examples kill most mutants of a method) at least as much as of
  the operators.
- **The 1.5.0 additions are not the cost.** The 17 operators added in 1.5.0
  that fired on the corpus (`variable_read_to_nil`, `short_circuit_to_eager`,
  `constant_namespace_strip`, `index_write_to_value`, `index_receiver_to_self`,
  `index_to_key_predicate`, `constant_read_to_nil`, ...) produce 388 mutants
  (7.1%) and 5.9% of killtime. `array_literal` and `hash_literal` (delete-each)
  are 1.1% and 0.2%.
- **Least subsumed, most informative**: `block_pass_removal` (37%),
  `optional_default_injection` (74% subject / 27% line),
  `optional_parameter_to_required`, `forwarded_argument_drop`, and the
  `integer_literal` neighbours `n + 1` / `n - 1` (below). These carry
  requirements no other operator generates.
- **Most subsumed** (>= 98% at subject level): `negation_insertion`,
  `conditional_flip`, `keyword_argument_removal`, `index_receiver_to_self`,
  `local_variable_assignment`, `short_circuit_to_eager`, `boolean_expression_to_nil`.

### Variants

**`integer_literal` by variant**

| variant | mutants | share | killtime s | time share | killed | survived | timed out | other | kill rate | subsumed (line) | subsumed (subject) |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| from_zero(+1/-1) | 36 | 21.2% | 11.0 | 21.4% | 14 | 22 | 0 | 0 | 38.9% | 79.3% | 89.8% |
| nil | 41 | 24.1% | 10.5 | 20.4% | 27 | 14 | 0 | 0 | 65.9% | 96.2% | 98.0% |
| width_sentinel | 29 | 17.1% | 10.4 | 20.2% | 18 | 11 | 0 | 0 | 62.1% | 84.2% | 88.3% |
| succ | 18 | 10.6% | 8.5 | 16.4% | 10 | 8 | 0 | 0 | 55.6% | 37.7% | 42.0% |
| zero | 29 | 17.1% | 6.2 | 12.1% | 24 | 5 | 0 | 0 | 82.8% | 86.5% | 89.4% |
| pred | 17 | 10.0% | 4.9 | 9.6% | 12 | 5 | 0 | 0 | 70.6% | 19.9% | 51.9% |
| **total** | 170 | 100% | 51.6 | 100% | 105 | 65 | 0 | 0 | 61.8% | 75.0% | 82.4% |

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

- The `integer_literal` neighbours carry the boundary information: `n - 1` is
  20% subsumed at line level and `n + 1` 38%, with `forwarded_argument_drop`
  and `optional_default_injection` the least redundant mutants in the corpus; dropping either alone loses 8 and 5 kills nothing else
  carries. Keep both.
- The `nil` replacement of a literal is 96-98% subsumed for integers and
  88-96% for strings: replacing an operand with `nil` raises on the first use,
  so any test that executes the line kills it, and the line's other mutants
  are killed by a subset of the same tests. Dropping the `nil` variants of
  `integer_literal`, `string_literal` and `float_literal` loses no kill with a
  failing example (2 load-time kills on redmine) and no survivor line.
- The `integer_literal` width sentinel (new in 1.5.0) is 29 mutants (0.5%),
  84-88% subsumed; dropping it alone loses 1 kill. Not worth a change either
  way.

## Dropping operators

### One at a time

Dropping any single operator loses almost nothing: for nearly every operator,
each kill is subsumed by a kept mutant of the same method, and almost every
survivor shares its line with a kept survivor. Selected rows (all targets):

| operator | mutants | killtime s | time share | kills | kills not subsumed | survivors | survivor lines lost |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| method_call_removal | 393 | 60.8 | 7.4% | 235 | 8 | 158 | 4 |
| integer_literal | 170 | 51.6 | 6.3% | 105 | 21 | 65 | 2 |
| method_body_replacement | 310 | 46.3 | 5.7% | 217 | 0 | 91 | 4 |
| symbol_literal | 328 | 38.3 | 4.7% | 160 | 20 | 168 | 0 |
| argument_nil_substitution | 302 | 36.7 | 4.5% | 152 | 9 | 149 | 2 |
| statement_deletion | 197 | 28.2 | 3.4% | 124 | 5 | 73 | 2 |
| conditional_negation | 200 | 27.3 | 3.3% | 117 | 1 | 83 | 0 |
| string_literal:nil | 86 | 18.9 | 2.3% | 45 | 0 | 41 | 0 |
| conditional_branch | 110 | 16.9 | 2.1% | 66 | 0 | 44 | 0 |
| negation_insertion | 100 | 13.4 | 1.6% | 70 | 0 | 30 | 0 |
| variable_read_to_nil | 124 | 13.2 | 1.6% | 59 | 0 | 65 | 5 |
| string_literal:empty | 58 | 13.0 | 1.6% | 24 | 0 | 34 | 0 |
| conditional_flip | 85 | 11.3 | 1.4% | 60 | 0 | 25 | 0 |
| integer_literal:from_zero(+1/-1) | 36 | 11.0 | 1.4% | 14 | 1 | 22 | 0 |
| predicate_replacement | 88 | 10.7 | 1.3% | 61 | 0 | 27 | 0 |
| integer_literal:nil | 41 | 10.5 | 1.3% | 27 | 2 | 14 | 0 |
| integer_literal:width_sentinel | 29 | 10.4 | 1.3% | 18 | 1 | 11 | 0 |
| integer_literal:succ | 18 | 8.5 | 1.0% | 10 | 5 | 8 | 0 |
| argument_method_call_replacement | 62 | 8.5 | 1.0% | 22 | 0 | 40 | 2 |
| keyword_argument_removal | 70 | 8.0 | 1.0% | 36 | 2 | 34 | 0 |
| optional_default_injection | 52 | 7.4 | 0.9% | 33 | 6 | 19 | 1 |
| integer_literal:zero | 29 | 6.2 | 0.8% | 24 | 1 | 5 | 0 |
| block_pass_removal | 26 | 5.8 | 0.7% | 5 | 3 | 21 | 2 |
| constant_namespace_strip | 42 | 5.5 | 0.7% | 24 | 0 | 17 | 0 |
| boolean_operator_replacement | 44 | 5.4 | 0.7% | 34 | 0 | 10 | 0 |
| boolean_expression_to_nil | 43 | 5.2 | 0.6% | 32 | 0 | 11 | 0 |
| integer_literal:pred | 17 | 4.9 | 0.6% | 12 | 8 | 5 | 0 |
| float_literal:infinity | 4 | 0.3 | 0.0% | 4 | 0 | 0 | 0 |
| float_literal:nan | 2 | 0.1 | 0.0% | 2 | 0 | 0 | 0 |

### Together: redundancy is mutual

Single-operator redundancy does not add up. Operators subsume each other, so
the set of "redundant on its own" operators is not redundant as a set. A
leave-one-target-out check shows it: on all targets but one, pick every
operator or literal variant with >= 20 mutants whose drop-alone cost is 0
kills not subsumed and 0 survivor lines lost, then drop the picked set
together on the held-out target:

| held out | picked | dropped on held-out | killtime share | kills dropped | kills not subsumed | survivors dropped | survivor lines lost |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: |
| fx | 20 | 96 / 440 | 20.7% | 85 | 6 | 11 | 2 |
| dm-maybe | 14 | 117 / 611 | 19.5% | 84 | 2 | 32 | 1 |
| hp | 19 | 391 / 1412 | 27.3% | 298 | 19 | 93 | 5 |
| grape | 16 | 141 / 693 | 20.3% | 130 | 0 | 10 | 0 |
| i18n | 16 | 358 / 1837 | 19.3% | 88 | 0 | 269 | 10 |
| redmine | 20 | 128 / 500 | 24.8% | 79 | 17 | 49 | 3 |

The greedy pick loses 17-19 real kills on httparty and redmine (and 6 on the
fixture) that the training targets said were free. A trim has to be chosen as
a set and validated as a set.

### Proposed trim ("set B")

Set B was fixed before Redmine was measured: the operators and variants the
selection above picked in **every** fold over the other five projects, i.e.
redundant whichever of them is held out, plus `float_literal`'s `nil` (below
the 20-mutant floor, kept for consistency with the other literals):

- the `nil` variant of `integer_literal`, `string_literal`, `float_literal`
  (operator names stay, the other variants stay);
- `negation_insertion`, `conditional_flip` (both re-negate a condition that
  `conditional_negation` already negates);
- `boolean_operator_replacement` (`&&` <-> `||`: subsumed by
  `boolean_operand_promotion`'s `a && b` -> `a` / `b`, as the logic-mutant
  subsumption hierarchy predicts for the connector mutants: Kaminski, Ammann,
  Offutt, *Better predicate testing*, AST 2011);
- `conditional_branch`, `predicate_replacement`, `boolean_expression_to_nil`,
  `keyword_argument_removal`, `argument_method_call_replacement`.

Simulated on the default runs (each dropped mutant's measured duration taken
out; no re-run):

| target | mutants | dropped | killtime dropped s | killtime share | kills dropped | kills not subsumed by a kept mutant | survivors dropped | survivor lines lost | score before | score after |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| fx-pricing | 135 | 16 | 1.3 | 6.1% | 16 | 0 | 0 | 0 | 90.4% | 89.1% |
| fx-inventory | 177 | 16 | 3.2 | 13.2% | 14 | 0 | 2 | 0 | 92.7% | 93.2% |
| fx-grade | 128 | 21 | 5.4 | 13.8% | 18 | 0 | 3 | 0 | 82.8% | 82.2% |
| dm-maybe | 611 | 74 | 10.8 | 12.6% | 54 | 0 | 20 | 0 | 66.3% | 65.3% |
| hp | 1412 | 96 | 15.1 | 6.9% | 84 | 0 | 12 | 0 | 71.9% | 70.7% |
| grape | 693 | 153 | 29.2 | 21.8% | 145 | 0 | 8 | 0 | 87.7% | 85.7% |
| i18n | 1837 | 277 | 11.0 | 15.1% | 72 | 0 | 205 | 0 | 18.1% | 16.7% |
| redmine | 500 | 78 | 32.8 | 14.9% | 52 | 4 | 26 | 2 | 70.1% | 70.8% |
| **total** | 5493 | 731 (13.3%) | 108.8 | 13.3% | 455 | 4 | 276 | 2 | | |

On every target, every kill set B drops is subsumed by a kept mutant of the
same method, except 4 Redmine kills that are load-time crashes
(`validates_length_of :name, :maximum => nil` raises when the model loads; so
does dropping the `:maximum` keyword) and that any test loading the model
kills. Redmine was the last target run, after set B had been chosen from the
other targets' data, so it is the held-out check: 0 kills with a failing
example lost there either. (With Redmine in the training data the fold
selection no longer picks `integer_literal`'s `nil`, `keyword_argument_removal`
and `argument_method_call_replacement`: exactly the costs Redmine showed.) Two
survivor lines are lost on Redmine:
`self.custom_field_ids = tracker.custom_field_ids.dup` and the same for
`project_ids` (`argument_method_call_replacement` drops `.dup`, and nothing
else survives there). That is a real finding, a copy that no test checks, and
the price of including `argument_method_call_replacement`. **Set B'** = set B
without it keeps both lines: 669 mutants (12.2%) and 12.3% of killtime
simulated, 4 load-time kills and 0 survivor lines lost.

### Measured wall time

The simulation over-states the saving: the mutation planner removes
duplicate mutants and keeps the first operator in registry order, so a mutant
of a dropped operator often comes back under another operator that produces
the same code (`conditional_flip` and `negation_insertion` duplicate
`conditional_negation` on many conditions). Measured by running the default
set and set B alternately on the same tree (set B removed through the same
hook, `DROP_OPERATORS` / `DROP_VARIANTS`), two repeats each, Redmine one:

| target | mutants off | mutants on | Δ mutants | killtime off s | killtime on s | Δ killtime | wall off s (mean) | wall on s (mean) | Δ wall | killed mutants removed | score off | score on |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| fx-grade | 128 | 117 | -8.6% | 38.9 | 33.6 | -13.6% | 21.1 (21.2, 21.1) | 18.7 (18.6, 18.8) | -11.4% | 9 | 82.8% | 83.8% |
| dm-maybe | 611 | 569 | -6.9% | 88.4 | 77.1 | -12.7% | 44.2 (45.6, 42.9) | 40.2 (40.0, 40.4) | -9.1% | 43 | 66.3% | 65.2% |
| grape | 693 | 559 | -19.3% | 129.6 | 102.6 | -20.8% | 66.5 (66.4, 66.6) | 50.3 (52.9, 47.8) | -24.3% | 131 | 87.7% | 85.6% |
| i18n | 1837 | 1618 | -11.9% | 72.2 | 60.2 | -16.6% | 38.5 (37.8, 39.2) | 32.5 (31.9, 33.1) | -15.6% | 65 | 18.1% | 16.6% |
| hp | 1412 | 1341 | -5.0% | 215.4 | 198.7 | -7.7% | 110.5 (109.9, 111.1) | 103.0 (101.5, 104.4) | -6.8% | 73 | 71.9% | 70.5% |
| redmine | 500 | 448 | -10.4% | 199.1 | 200.1 | +0.5% | 201.9 (201.9) | 202.7 (202.7) | +0.4% | 43 | 70.1% | 70.0% |
| **total** | 5181 | 4652 | -10.2% | 743.5 | 672.3 | -9.6% | 482.7 | 447.4 | -7.3% | 364 | | |

"Killed mutants removed" counts killed mutants whose diff no longer appears
in the set-B run (by file, line and diff, whatever operator reports it).

Set B removes **10.2% of mutants and 9.6% of killtime; wall time falls 7%
summed over the targets (from -24% on grape to none on Redmine)**, against
13.3% simulated. Redmine shows no gain from 52 fewer mutants in a single
repeat: the same 500 mutants took 199 s of killtime here and 220 s in the
study's default run, run-to-run noise of the same size as the 15% set B takes
out there, which one repeat cannot resolve. Mutation scores move by -2.1 to +1.0 points.

## Decision

- **Default profile: no change now; the trim is a proposal for the
  maintainer.** Removing operators from `default` changes every user's
  mutant count and score, and `docs/versioning.md` lists only *adding* an
  operator to `default` as a minor change; whether removing one is a minor or
  a major change is the maintainer's call. The numbers for that call: set B
  takes out 10% of mutants and 7-10% of run time (up to 24% on a target heavy
  in conditions), loses no kill with a failing example that another mutant
  does not carry on 8 runs over 5 projects (4 load-time crash kills), and
  loses 2 survivor lines, both from `argument_method_call_replacement`; the
  recommended variant is set B' (without it), which keeps them and gives up
  about 1 point of killtime. Before moving anything, re-run the
  kill-set measurement (the hook below) on a wider corpus of real
  projects, since a set validated on one held-out target is thin evidence.
- **`fast` profile: not shipped.** A 7-10% saving does not justify a new
  public profile name that must keep its meaning for the whole 1.x line. It
  is smaller than what the engine work in this epic gave (about 50% on the
  fixture), and smaller than `skip_uncovered` / `--probe-first`, which remove
  mutants nobody's test reaches (up to 48% on i18n) instead of mutants a test
  does reach. If a wider corpus confirms set B', the cheaper route is the
  default-profile change above; a `fast` profile would only be worth it with
  a larger cut that accepts lost kills, which this data does not support.
- **Not proposed**: moving any 1.5.0 operator. They are 7% of mutants, and
  their subsumption is no higher than the old operators'. The
  `integer_literal` `n + 1` / `n - 1` neighbours are among the least
  redundant mutants in the corpus.
- **Noticed on the way, not changed**: `string_literal` turns a word of a
  `%w()` array into `""` and into `nil`, which inside `%w` are just two other
  words (`%w(a "" c)`, `%w(a nil c)`): two mutants with the same effect per
  word (Redmine `tracker.rb:28`, 12 mutants).

## Reproducing

Scripts used (kept outside the repository; they are measurement-only):

- **Kill-set hook**, loaded with `bundle exec ruby -r<hook> exe/evilution run
  ... --no-stop-on-kill` and `KILLSETS_OUT=<file.jsonl>`. It prepends
  `run_tests(mutation)` on `Evilution::Integration::RSpec` and
  `::Minitest` (resets a per-run list, then writes one JSON line per
  mutation: file, line, operator, subject, diff, failing ids) and collects the
  failing ids in `RSpec#build_result`
  (`Integration::RSpec::ExampleIds.failed(::RSpec.world)`) and
  `Minitest#run_minitest` (its `failed_ids`). With `DROP_OPERATORS=a,b` it
  removes operators from `Mutator::Registry.default`, and with
  `DROP_VARIANTS=op:variant,...` it filters the mutations
  `Registry#mutations_for` returns by the variant classifier below. It must
  be given after `bundle exec` (`-r` on the command line), not in `RUBYOPT`:
  it requires `evilution`, which has to resolve through the bundle.
- **Variant classifier**: the changed token of the diff's first `-`/`+` pair,
  widened to whole tokens; for `integer_literal` compared numerically (`zero`,
  `n + 1`, `n - 1`, `±1` from `0`, width sentinel, `nil`).
- **Analysis**: matches the default run and the kill-set records by file,
  line, operator and diff, then computes the tables above (subsumption with
  fractional dominator credit, drop cost, leave-one-target-out).
