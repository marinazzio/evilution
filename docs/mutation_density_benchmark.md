# Mutation Density Benchmark Methodology

## Goal

Track and close the mutation density gap between evilution and a reference
mutation testing tool.
Current gap: **1.8-2.6x** (evilution generates fewer mutations).
Target: **< 1.5x** across the benchmark corpus.

## Metric

**Density ratio** = `reference_mutations / evilution_mutations` per file.

A ratio of 1.0 means parity. Values above 1.0 mean the reference tool generates
more. The aggregate ratio is computed from total mutations across all benchmark
files (not an average of per-file ratios, which would over-weight small files).

## Measurement Protocol

### Benchmark corpus

Select **10 files** from a real-world Rails project covering diverse patterns:

| Slot | Category             | Example                          |
|------|----------------------|----------------------------------|
| 1    | Controller           | `app/controllers/*_controller.rb`|
| 2    | Model (ActiveRecord) | `app/models/*.rb`                |
| 3    | Service object       | `app/services/*.rb`              |
| 4    | Validator            | `app/validators/*.rb`            |
| 5    | Concern / mixin      | `app/models/concerns/*.rb`       |
| 6    | Helper               | `app/helpers/*.rb`               |
| 7    | Formatter / presenter| `app/presenters/*.rb`            |
| 8    | Lib utility          | `lib/*.rb`                       |
| 9    | Job / worker         | `app/jobs/*.rb`                  |
| 10   | Configuration / DSL  | `config/initializers/*.rb`       |

Files should be **50-300 LOC** (enough mutations to be meaningful, small enough
to run quickly). The exact file list is stored in the benchmark config file
(`scripts/benchmark_density.yml`).

### Tool configuration

Both tools must run with equivalent settings:

- **evilution**: default operators, no `--skip-heredoc-literals`, no ignore patterns
- **reference tool**: default operator set, no timeout (we only count, not run)

The benchmark counts **generated mutations**, not killed/survived. This isolates
operator coverage from test quality.

### Running the benchmark

```bash
# Count-only mode (fast, no test execution):
scripts/benchmark_density scripts/benchmark_density.yml

# Full output with per-file breakdown:
scripts/benchmark_density scripts/benchmark_density.yml --verbose
```

### Output

The script produces a table:

```
File                          Evilution  Reference  Ratio
app/models/user.rb                  42         78  1.86x
app/services/payment.rb             31         52  1.68x
...
TOTAL                              312        534  1.71x
```

And a summary: `Density ratio: 1.71x (target: < 1.50x)`.

## When to Run

- **Before each release** that adds new operators
- **After closing operator issues** from the gap analysis epic (GH #515)
- **On demand** when evaluating whether a proposed operator is worth adding

## Interpreting Results

- **Ratio < 1.5x**: target met
- **Ratio 1.5-2.0x**: progress, but more operators needed
- **Ratio > 2.0x**: significant gap remains
- **Per-file outliers**: files with ratio > 3.0x likely expose a missing operator category

Not all extra mutations from the reference tool are valuable. Some produce
equivalent mutants (semantically identical code). The head-to-head comparison
(GH #523) classifies each extra mutation as signal vs noise. The density ratio
is a **coarse progress metric**, not a quality score.
