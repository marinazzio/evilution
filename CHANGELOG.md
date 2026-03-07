# Changelog

## [Unreleased]

### Removed

- **Parallel execution** (`--jobs` flag) — simplifies codebase for AI-agent-first design; will be reintroduced later

## [0.1.0] - 2026-03-02

### Added

- **18 mutation operators**: ArithmeticReplacement, ComparisonReplacement, BooleanOperatorReplacement, BooleanLiteralReplacement, NilReplacement, IntegerLiteral, FloatLiteral, StringLiteral, ArrayLiteral, HashLiteral, SymbolLiteral, ConditionalNegation, ConditionalBranch, StatementDeletion, MethodBodyReplacement, NegationInsertion, ReturnValueRemoval, CollectionReplacement
- **Prism-based AST parsing** with source-level surgery via byte offsets
- **Fork-based isolation** for safe mutation execution
- **RSpec integration** for test execution
- **Parallel execution** with configurable worker count (`--jobs`)
- **Diff-based targeting** to mutate only changed code (`--diff HEAD~1`)
- **Coverage-based filtering** — skip mutations on lines no test exercises
- **JSON output** for AI agents and CI pipelines (`--format json`)
- **CLI output** with human-readable mutation testing results
- **Actionable suggestions** for surviving mutants
- **Configuration file** support (`.evilution.yml`)
- **`evilution init`** command to generate default config
- **Error handling** with clean exit codes (0=pass, 1=fail, 2=error)
