# Operator Addition Prioritization

Date: 2026-04-09
Based on: EV-250 classification of 3,901 reference tool mutations across 10 files

## Current Status

- Density ratio: **1.34x** (target: < 1.5x) — **already passing**
- Evilution: 68 operators covering 14/20 reference categories fully, 4 partially
- Effective signal gap after removing noise: ~1.0-1.1x (near parity)

## Prioritized Operator Additions

Ranked by: (a) signal frequency, (b) implementation complexity, (c) equivalent mutant rate.

### Priority 1: High signal, low complexity

| # | Operator | Signal Count | Complexity | Equiv. Rate | Notes |
|---|----------|-------------|-----------|-------------|-------|
| 1 | `[]` → `.at()` substitution | 60 | Low | Low (~10%) | Catches unchecked array/hash access. Single AST node transform. New operator needed. |

**Rationale:** Only uncovered category with real signal. `.at()` returns nil
instead of raising on out-of-bounds, exposing missing bounds checks. Simple to
implement — match `CallNode` with name `[]` on collection receivers, emit `.at()`
variant.

### Priority 2: Improve existing coverage (partial gaps)

| # | Operator | Gap Area | Complexity | Equiv. Rate | Notes |
|---|----------|----------|-----------|-------------|-------|
| 2 | Regex simplification (EV-230, #514) | 27 | Medium | Low (~15%) | Quantifier removal, anchor removal, character class simplification. Already scoped. |
| 3 | Block pass removal (`&:method`) | 5 | Low | Medium (~30%) | Remove `&:symbol` block pass. Marginal count but trivial to add. |

**Rationale:** EV-230 is already scoped with a GH issue. Block pass removal is
minimal effort for minimal gain — include only if doing a batch of small operators.

### Priority 3: Do not implement

| # | Category | Count | Reason |
|---|----------|------:|--------|
| — | Guard clause restructuring | 570 | Pure noise — syntactic reformatting, not semantic mutation |
| — | Receiver self-swap (remaining) | ~140 | Mostly equivalent — `self.method` vs `method` rarely matters |
| — | Complex compound mutations | ~288 | Noise portion of multi-statement changes; not decomposable into discrete operators |

## Implementation Order

1. **EV-230** (#514) — Regex simplification operators (already scoped, medium complexity, 27 signal mutations)
2. **New: `IndexToAt`** — `[]` → `.at()` substitution (60 signal mutations, low complexity)
3. **New: `BlockPassRemoval`** — `&:method` removal (5 signal mutations, trivial)

## Impact Assessment

| Scenario | Estimated Ratio | Delta |
|----------|----------------|-------|
| Current | 1.34x | — |
| After adding all Priority 1+2 | ~1.31x | -0.03x |

The density gap is already within target. These additions improve **signal
coverage** (catching real bugs that reference tool catches and evilution misses)
rather than closing the headline ratio, which is already healthy.

## Recommendation

The density gap research (EV-238) can be considered **successful** — the 1.5x
target is met at 1.34x. Remaining work should focus on signal quality (regex
mutations, bounds checking) rather than chasing the ratio lower. The reference
tool's ~15% noise inflation means its raw count is not a meaningful target for
exact parity.
