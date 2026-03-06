# Mutant Gem — Deep Technical Analysis

## Executive Summary

**Mutant is a fully independent, ground-up Ruby mutation testing engine** — not a wrapper around
anything. It is the most technically sophisticated mutation testing tool in the Ruby ecosystem,
backed by IEEE-published research. However, it is **not open source** despite its code being
publicly visible on GitHub. It uses a custom commercial EULA: free for public OSS projects,
**$90/month per developer** for commercial/private use.

This creates a clear gap in the Ruby ecosystem — and an opportunity for a truly free alternative.

---

## 1. What Is Mutation Testing?

Mutation testing validates test suite quality by:

1. Parsing source code into an AST
2. Applying small, deliberate code changes ("mutations") — e.g., `>=` → `>`
3. Running the test suite against each mutated version
4. If tests pass despite the change → the mutant **survived** (test gap found)
5. If tests fail → the mutant was **killed** (tests caught the defect)

**Mutation score** = killed / total non-equivalent mutants. A score of 100% means every
behavioral change was caught by tests. This is far more rigorous than line coverage.

---

## 2. Is Mutant a Wrapper or Independent Tool?

**Fully independent.** Every component is built from scratch:

| Component | Implementation |
|---|---|
| AST parsing | Uses `parser` gem (Whitequark) to parse Ruby → S-expression AST |
| AST unparsing | Uses `unparser` gem (also by mbj) to convert mutated AST → Ruby source |
| Mutation operators | ~60 custom `Mutator::Node` subclasses, one per AST node type |
| Regex mutation | Deep sub-expression mutation via `regexp_parser` gem |
| Process isolation | Custom `fork(2)` + pipe IPC per mutation |
| Parallel execution | Custom thread-based worker system (`Mutant::Parallel`) |
| Test integration | Abstract adapter pattern for RSpec and Minitest |
| Test selection | Expression prefix-matching (convention-based, not tracing) |
| Reporting | Custom CLI reporter with diffs and coverage stats |
| Config | YAML-based with immutable value objects |

No delegation to any external mutation engine exists anywhere in the codebase.

---

## 3. Architecture — How It Works

### Execution Pipeline

```
CLI → Config Load → Bootstrap → Env Build → Runner (parallel) → Report
```

### Step-by-Step

**1. Config** (`ruby/lib/mutant/config.rb`)
Loads `mutant.yml` / `.mutant.yml` / `config/mutant.yml`. Immutable struct holding:
coverage criteria, integration choice, isolation mode, parallelism (`jobs`), matcher
expressions, operator set (Full vs Light), usage mode (opensource/commercial).

**2. Bootstrap** (`ruby/lib/mutant/bootstrap.rb`)
- Loads hooks
- Applies `$LOAD_PATH` extensions and `require`s the user's application
- Scans `ObjectSpace.each_object(Module)` to discover all loaded Ruby constants
- Parses each constant name into an expression (e.g., `Person#adult?`)
- Runs the `Matcher` to filter subjects to those matching CLI targets
- Generates all mutations for selected subjects
- Sets up the test integration (RSpec/Minitest)
- Returns an immutable `Env` object

**3. Per-Mutation Execution**
For each mutation:
1. `Isolation::Fork` forks a child process
2. Inside the child, `Loader.call` uses Ruby's `eval` to monkey-patch the mutated
   source into the live constant
3. The test integration runs matched tests
4. Result (pass/fail) is marshalled back via anonymous pipe
5. Parent classifies: killed (tests failed) or survived (tests passed)
6. Timeout handling: `IO.select` + `waitpid2(WNOHANG)`, then `SIGKILL` on deadline

**4. Test-to-Subject Matching**
`Selector::Expression` maps subjects to tests via **prefix matching on expression strings**:
- Subject `Person#adult?` matches RSpec group `Person::adult?`
- This is convention-based — no runtime tracing or static analysis

### Key Modules

| Module | Role |
|---|---|
| `Mutant::World` | DI container for all I/O (process, kernel, io, thread, marshal) |
| `Mutant::Mutator` | Abstract base for mutation generators |
| `Mutant::Mutator::Node` | Dispatches to concrete subclasses by AST node type |
| `Mutant::Mutation` | One mutation instance (`Evil`, `Neutral`, `Noop` subclasses) |
| `Mutant::Isolation::Fork` | Fork + pipe per mutation |
| `Mutant::Integration` | Abstract test framework adapter |
| `Mutant::Subject` | One testable code unit (e.g., one method) |
| `Mutant::Zombifier` | Namespace-wrapping `require` interceptor |
| `Mutant::Usage` | Runtime license enforcement |

---

## 4. Mutation Operators

### 4.1 Operator Replacements (119 rules in Full mode)

Selected examples from `Mutation::Operators::Full::SELECTOR_REPLACEMENTS`:

```
Arithmetic:    + ↔ -,  * ↔ /,  % → /,  ** → *
Comparison:    < → [==, eql?, equal?],  <= → [<, ==],  > → [==],  >= → [>]
Equality:      == → [!=, eql?, equal?],  != → [==]
Bitwise:       & ↔ |,  ^ ↔ & and |,  << ↔ >>
Boolean:       && ↔ ||
```

### 4.2 Collection/Method Replacements

```
all? ↔ any? ↔ none?      map → each          select ↔ reject
first ↔ last             min ↔ max            empty? → any?
gsub → sub               downcase ↔ upcase    flat_map → map
start_with? ↔ end_with?  send → public_send   dig → fetch chain
```

### 4.3 Literal Mutations

| Type | Mutations |
|---|---|
| Integer | `0`, `1`, `value+1`, `value-1` |
| Float | `0.0`, `1.0`, `NaN`, `Infinity`, `-Infinity` |
| Boolean | `true` ↔ `false` |
| String | `""` (empty) |
| Array | empty, remove each element, mutate each element |
| Hash | empty, remove each pair, mutate keys/values |
| Regex | never-matching pattern, empty body, deep sub-expression mutations |

### 4.4 Control Flow Mutations

- `if`: force condition to `true`/`false`, remove branches
- `return`: remove return value, emit value alone
- `begin` (sequence): delete/mutate individual statements
- `rescue`/`ensure`: remove clauses
- `break`/`next`/`yield`/`super`: emit singletons, mutate arguments

### 4.5 Method Definition Mutations

Replace body with: `raise`, `super`, `nil`, `[]`, `{}`, `""`, `0`, `0.0`

### 4.6 Light vs Full Mode

`Light` mode removes 4 entries (`==`, `eql?`, `first`, `last`) to reduce noise.

---

## 5. Licensing — The Critical Detail

| Aspect | Detail |
|---|---|
| License type | Custom commercial EULA (NOT MIT/Apache/GPL) |
| SPDX ID | `NOASSERTION` (not a recognized open-source license) |
| Open source use | Free with `--usage opensource` for public repos under OSI license |
| Commercial use | **$90/month per developer** ($900/year) |
| Enterprise (20+) | Custom pricing |
| Governing law | Maltese law (Schirp DSO LTD, Malta) |
| Prohibitions | Reverse engineering, redistribution, sublicensing, competitive products, benchmark publishing |
| Runtime enforcement | `Mutant::Usage` class validates declared usage mode against repo visibility |

The source went commercial **around March 2019** after ~7-8 years of free availability. The
`mutant-license` companion gem first appeared on RubyGems on March 24, 2019.

---

## 6. Dependencies

| Gem | Version | Purpose |
|---|---|---|
| `parser` | `~> 3.3.10` | Ruby source → AST (by Whitequark) |
| `unparser` | `~> 0.8.2` | AST → Ruby source (by mbj) + functional primitives |
| `regexp_parser` | `~> 2.10` | Regex pattern → regex AST for deep mutation |
| `sorbet-runtime` | `~> 0.6.0` | Runtime type annotations |
| `diff-lcs` | `>= 1.6, < 3` | Diff computation for reports |
| Ruby | `>= 3.2` | Minimum runtime version |

Integration gems: `mutant-rspec` (rspec-core >= 3.10), `mutant-minitest` (minitest >= 5).

Optional: A Rust crate (`mutant/src/`) reimplements the process management and IPC layers
for performance — this is opt-in and does not affect the mutation logic.

---

## 7. Competitive Landscape — Free Alternatives by Language

| Language | Best Free Tool | License | Maturity |
|---|---|---|---|
| Java | **PIT (pitest.org)** | Apache 2.0 | Gold standard |
| JavaScript/TS | **StrykerJS** | Apache 2.0 | Excellent |
| C# / .NET | **Stryker.NET** | Apache 2.0 | Good |
| PHP | **Infection** | BSD-3 | Good |
| Python | **mutmut** | Apache 2.0 | Moderate |
| Rust | **cargo-mutants** | MIT | Good |
| C/C++ | **Mull** | Apache 2.0 | Good (LLVM-level) |
| Go | **go-gremlins** | Apache 2.0 | Moderate |
| Swift | **Muter** | MIT | Moderate |
| **Ruby** | **None dominant** | — | **Gap in ecosystem** |

Ruby has the weakest free mutation testing coverage of any major language. Alternatives
like `moots` (MIT) and `Heckle` (dead since 2009) are far behind mutant's capabilities.

---

## 8. Interpreted vs Compiled Languages — Why Interpreted First

### The fundamental asymmetry

For **interpreted languages** (Ruby, Python, JS, PHP, Elixir), each mutation costs:
```
fork process → eval/load mutated source → run tests → collect result
```
No compilation step. The mutated source is injected directly into a running runtime.
This takes milliseconds of overhead per mutation beyond the test execution itself.

For **compiled languages** (Rust, Go, C/C++, Java), each mutation naively costs:
```
modify source → recompile entire project → run tests → collect result
```
Compilation can take seconds to minutes per mutant. For a project with 10,000 mutants and
a 30-second build, that's 83+ hours of just compilation.

### How compiled-language tools work around this

| Tool | Language | Strategy | Trade-off |
|---|---|---|---|
| **PIT** | Java | Mutates JVM **bytecode** (not source). Compile once, mutate the `.class` files in memory. | Loses source-level correspondence; requires bytecode expertise |
| **Mull** | C/C++ | Mutates LLVM **IR/bitcode**. Compile once to `.bc`, mutate IR instructions. | Requires LLVM toolchain; IR ≠ source (one line → many instructions) |
| **cargo-mutants** | Rust | Mutates source, relies on Rust's **incremental compilation**. | Still slow — each mutant triggers partial recompile |
| **Stryker.NET** | C# | Mutates the Roslyn **syntax tree** in-process. | Tied to .NET compilation pipeline |

**Bottom line**: compiled-language tools need a fundamentally different architecture
(bytecode/IR manipulation) to be practical. Interpreted-language tools share a common
pattern (parse → mutate AST → eval/load → test) that generalizes cleanly across languages.

### Multi-language expansion path (interpreted languages)

The core engine (mutation operators, process isolation, parallel execution, reporting) is
largely language-agnostic. What changes per language:

| Component | Language-specific? | Notes |
|---|---|---|
| AST parser | **Yes** | Ruby: `prism`. Python: `ast` module. JS: `acorn`/`babel`. |
| AST → source | **Yes** | Ruby: `unparser`/`prism`. Python: `ast.unparse`. JS: `escodegen`. |
| Mutation operators | **Partially** | Arithmetic/comparison/boolean operators are universal. Method replacements are language-specific. |
| Process isolation | **Mostly no** | Fork works everywhere on Linux/macOS. |
| Test integration | **Yes** | Ruby: RSpec/Minitest. Python: pytest. JS: Jest/Vitest. |
| Test selection | **No** | Coverage-based approach works in any language. |

A well-designed tool could share 60-70% of its code across languages, with
language-specific adapters for parsing, unparsing, and test framework integration.

---

## 9. Design for AI Agents — The Primary Audience

### Why this changes everything

Traditional mutation testing tools (mutant, PIT, StrykerJS) are designed for **human
developers** running them occasionally to audit test quality. The output is optimized for
human reading: progress bars, colored diffs, summary statistics.

If the primary consumer is an **AI agent** that needs fast, actionable feedback to improve
code and tests it just generated, the design priorities shift dramatically:

### Priority 1: Structured, machine-readable output

AI agents need JSON, not pretty-printed tables.

```json
{
  "summary": {
    "total": 47,
    "killed": 41,
    "survived": 5,
    "timed_out": 1,
    "score": 0.891
  },
  "survived": [
    {
      "file": "lib/user.rb",
      "line": 23,
      "method": "User#adult?",
      "original": "@age >= 18",
      "mutated": "@age > 18",
      "operator": "boundary",
      "suggestion": "Add a test for the boundary case where age == 18"
    }
  ]
}
```

The `suggestion` field is key — the tool can include actionable hints that an AI agent
can directly act on. A human would read a diff and figure it out; an agent benefits from
explicit guidance.

### Priority 2: Speed — incremental/diff-based mutation

AI agents iterate in tight loops: generate code → run tests → check mutation score →
fix gaps → repeat. Full-project mutation is too slow for this workflow.

**Critical feature: mutate only changed code.**

```bash
# Only mutate methods touched in the last commit
mutest run --diff HEAD~1

# Only mutate a specific file
mutest run --target lib/user.rb

# Only mutate a specific method
mutest run --target "User#adult?"
```

This is the single most important performance optimization for the AI agent use case.
Mutant supports this (`--since` flag), and it should be a first-class feature, not an
afterthought.

### Priority 3: Fast startup

AI agents may call the tool hundreds of times in a session. Startup overhead matters.

- Avoid scanning `ObjectSpace` for all constants (mutant's approach) — it's thorough but
  slow. Instead, target specific files/methods directly.
- Preload the project once if possible (daemon mode or warm cache).
- Consider a **server mode**: a long-running process that accepts mutation requests via
  stdin/socket, avoiding Ruby boot time on each invocation.

### Priority 4: Exit codes for automation

```
Exit 0: all mutants killed (score == 100%)
Exit 1: surviving mutants found
Exit 2: tool error / invalid config
```

Simple, standard, automatable.

### Priority 5: Minimal configuration

AI agents shouldn't need to generate a `mutant.yml`. Sensible defaults + CLI flags:

```bash
# Zero-config: detect test framework, mutate everything
mutest run

# Targeted: just this file
mutest run lib/user.rb

# With threshold
mutest run --min-score 0.9 lib/user.rb
```

### What CI integration is NOT needed for

The user correctly identifies that CI is not the primary value proposition here. AI agents
don't push to CI and wait — they run the tool locally, read the output, and iterate.

That said, CI support is trivially achieved by the CLI design above (exit codes + JSON
output), so it comes nearly for free without special effort.

---

## 10. Feasibility Assessment — Building a Free Ruby Mutation Tester

### What You'd Need to Build

| Component | Effort | Notes |
|---|---|---|
| AST parsing | **Low** | Use `prism` (Ruby's official parser, MIT, ships with Ruby 3.3+) |
| AST → source | **Low** | `prism` can round-trip, or use `unparser` gem (MIT) |
| Mutation operators | **High** | The core work — start with ~15-20, expand over time |
| Process isolation | **Medium** | Fork + pipe pattern is well-understood |
| Parallel execution | **Medium** | Thread pool distributing fork workers |
| RSpec integration | **Medium** | Hook into `rspec-core` to run selected examples |
| Minitest integration | **Medium** | Similar adapter pattern |
| Coverage filtering | **Low-Medium** | Skip uncovered mutations using Ruby's `Coverage` module |
| JSON reporting | **Low** | Structured output for AI agents |
| CLI | **Low** | Argument parsing + orchestration |
| Config system | **Low** | YAML loading with sensible defaults |
| Timeout handling | **Low** | IO.select + waitpid + SIGKILL pattern |
| Diff-based targeting | **Medium** | Git integration to identify changed methods |

### Key Technical Decisions

1. **Parser choice**: `prism` — it's the future. Ships with Ruby 3.3+, faster than
   `parser` gem, maintained by the Ruby core team. Mutant itself is migrating to it.

2. **Mutation granularity**: Start with Google's 5 essential operators (AOR, LCR, ROR,
   UOI, SBR) plus Ruby-specific ones (method replacements, boolean literals, nil injection).
   Expand to mutant's full 119 rules over time.

3. **Process model**: Fork-based. Guarantees clean state, fast (no re-boot), works well
   with Ruby's GC.

4. **Coverage filtering**: Using Ruby's `Coverage` module. Run the test suite once with
   coverage tracking, then skip mutations on lines that no test exercises. Ruby's Coverage
   provides aggregate per-file line hit counts (not per-test-file tracking), so the
   practical win is filtering out uncovered mutations entirely.

5. **Output format**: JSON primary, human-readable secondary. The JSON schema should
   include actionable suggestions per surviving mutant.

6. **Diff-based mode**: First-class feature. Parse git diff, identify changed methods,
   only generate mutations for those methods. This is the killer feature for AI agents.

### Realistic Scope for an MVP

An MVP that covers the most valuable 80% of mutation testing:

- **~15-20 mutation operators** covering: arithmetic, comparison, boolean, statement
  deletion, literal replacement, method body replacement
- **RSpec integration** (most popular Ruby test framework)
- **Fork-based isolation** with timeout
- **Parallel execution** (configurable job count)
- **JSON + CLI reporting** with actionable suggestions
- **Coverage-based filtering** using Ruby's `Coverage` module
- **Diff-based targeting** (mutate only changed code)
- **MIT license**

### Challenges to Watch

1. **Performance**: Mutation testing is inherently expensive — fork + test per mutation.
   Coverage-based filtering + diff-based targeting are critical.
2. **Ruby version support**: New syntax requires parser updates. Using `prism` helps since
   it's maintained by the Ruby core team and tracks new syntax immediately.
3. **Metaprogramming**: Ruby's dynamic nature (method_missing, define_method, eval) makes
   some code unmutatable by static AST analysis alone. Accept this limitation initially.
4. **Prism API stability**: Prism is relatively new. API may evolve. Worth tracking.

### Multi-language expansion (future)

Once the Ruby core is solid, adding Python support is the natural next step:
- Python's `ast` module provides parsing + unparsing built into the stdlib
- `pytest` is the dominant test framework with good programmatic API
- `coverage.py` provides coverage data
- Python also lacks a dominant, well-maintained free mutation tool (mutmut is moderate)
- Fork-based isolation works identically

After Python: Elixir (AST macros are first-class), PHP (Infection exists but another
perspective is valuable), JavaScript (StrykerJS exists and is excellent — lower priority).

---

## 11. Conclusions

1. **Mutant is impressive engineering** — fully independent, ~60 mutator classes, 119
   operator replacement rules, deep regex mutation, Rust performance layer.

2. **The commercial license creates a real market gap** — Ruby is the only major language
   without a dominant free mutation testing tool.

3. **Building a free alternative is feasible** — the core dependencies (`prism`) are
   MIT-licensed, the fork-based isolation pattern is well-understood, and you can start
   with a focused operator set.

4. **AI-agent-first design is a differentiator** — no existing mutation tool is optimized
   for machine consumption. JSON output, diff-based targeting, fast startup, and actionable
   suggestions would make this uniquely valuable in the emerging AI-assisted development
   workflow.

5. **Interpreted languages share a common architecture** — Ruby first, then Python, Elixir,
   PHP. The core engine (isolation, parallelism, reporting) generalizes cleanly. Compiled
   languages require fundamentally different approaches (bytecode/IR mutation) and should
   be deferred.

6. **Recommended approach**: Use `prism`, start with ~15-20 operators, implement
   coverage-based filtering + diff-based targeting, output structured JSON, target
   RSpec first, and ship an MIT-licensed gem.
