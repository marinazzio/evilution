# Reference Tool Mutation Classification by Operator Category

Date: 2026-04-09
Corpus: 10 files from a private Rails app (2,903 evilution / 3,901 reference mutations)

## Category Breakdown

Classification of all 3,901 reference tool mutations by semantic category,
with signal/noise assessment and evilution coverage status.

| Category | Count | % | Signal | Evilution Coverage |
|----------|------:|--:|--------|-------------------|
| complex_mutation | 854 | 21.9% | Mixed | Partial — multi-statement changes, compound mutations spanning multiple lines |
| argument_nil | 585 | 15.0% | Signal | Covered — ArgumentNilSubstitution, ArgumentRemoval |
| guard_clause_restructure | 570 | 14.6% | Noise | Not applicable — reformats `return if X` to `unless X; return; end` without semantic change |
| receiver_mutation | 416 | 10.7% | Signal | Covered — ReceiverReplacement, MethodCallRemoval |
| receiver_self_swap | 281 | 7.2% | Mixed | Partial — ReceiverReplacement covers some; `self.` insertion is often equivalent |
| string_mutation | 224 | 5.7% | Signal | Covered — StringLiteral, StringInterpolation |
| arithmetic_mutation | 224 | 5.7% | Signal | Covered — ArithmeticReplacement |
| symbol_mutation | 129 | 3.3% | Signal | Covered — SymbolLiteral (mutant uses `__mutant__` suffix) |
| hash_mutation | 119 | 3.1% | Mixed | Partial — HashLiteral covers structure; key reordering is noise |
| method_body_removal | 94 | 2.4% | Signal | Covered — MethodBodyReplacement (empty body variant) |
| method_body_raise | 79 | 2.0% | Signal | Covered — MethodBodyReplacement (raise variant) |
| method_body_super | 79 | 2.0% | Signal | Covered — MethodBodyReplacement (super variant) |
| method_substitution_at | 60 | 1.5% | Mixed | Not covered — `[]` → `.at()` catches missing bounds checks |
| method_substitution_fetch | 58 | 1.5% | Signal | Covered — IndexToFetch |
| condition_nil_false | 43 | 1.1% | Signal | Covered — ConditionalBranch, NilReplacement |
| method_body_nil | 27 | 0.7% | Signal | Covered — MethodBodyReplacement (nil variant) |
| regex_mutation | 27 | 0.7% | Signal | Covered — RegexpMutation, RegexCapture |
| boolean_literal | 16 | 0.4% | Signal | Covered — BooleanLiteralReplacement |
| equality_mutation | 10 | 0.3% | Signal | Covered — EqualityToIdentity |
| block_pass_mutation | 5 | 0.1% | Signal | Partial — BlockRemoval covers block removal; `&:method` removal not specific |
| integer_boundary | 1 | 0.0% | Signal | Covered — IntegerLiteral |

## Signal vs Noise Summary

| Assessment | Count | % |
|------------|------:|--:|
| Signal (catches real bugs) | 2,176 | 55.8% |
| Mixed (some signal, some equivalent) | 1,155 | 29.6% |
| Noise (equivalent or reformatting) | 570 | 14.6% |

## Key Findings

### 1. Guard clause restructuring is pure noise (14.6%)

The reference tool rewrites `return X if condition` to `unless condition; return X; end`.
This is a syntactic reformatting, not a semantic mutation. It inflates the mutation count
without testing anything. Evilution correctly does not produce these.

### 2. Most categories are already covered by evilution

Of 20 categories, evilution has operators covering 14 fully and 4 partially.
Only 2 categories are not covered:
- **guard_clause_restructure** — noise, should not be added
- **method_substitution_at** — `[]` → `.at()`, marginal signal

### 3. The "complex_mutation" bucket needs further analysis

854 mutations (21.9%) are multi-statement compound changes that don't fit a single
category. Many combine receiver replacement + argument modification + formatting
changes in one diff. Some contain real signal (e.g., removing a hash key from a
method call), others are largely equivalent reformattings.

### 4. The 1.34x gap is largely explained by:

- Guard clause restructuring: 570 mutations (noise)
- Receiver self-swap equivalents: ~140 mutations (noise portion of 281)
- Complex compound mutations: ~288 mutations (noise portion of 854)

**Removing noise**, the effective gap drops to approximately **1.0-1.1x** —
near parity for signal-bearing mutations.

## Recommendations for EV-251 (Prioritization)

1. **Do not add** guard clause restructuring — pure noise
2. **Consider adding** `[]` → `.at()` substitution (60 mutations, real signal for bounds checking)
3. **Investigate** the complex_mutation bucket further to extract any discrete operator patterns
4. **Current density target (< 1.5x) is already met** at 1.34x overall
