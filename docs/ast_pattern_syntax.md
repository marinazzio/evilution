# AST Pattern Language Syntax

Design document for the `ignore_patterns` configuration in Evilution.

## Overview

The AST pattern language allows precise, semantic exclusion of mutations. Instead of
file/line targeting, patterns match Prism AST node structures so that mutations on
logging, debugging, or infrastructure code can be suppressed declaratively.

Patterns are specified in `.evilution.yml` under the `ignore_patterns` key:

```yaml
ignore_patterns:
  - "call{name=log}"
  - "call{receiver=call{name=logger}}"
  - "call{name=puts|warn|pp}"
```

## Syntax

### Node Type Matching

A pattern starts with a **node type** name. Node types are lowercased, underscore-separated
names derived from Prism node classes with the `Node` suffix stripped:

| Pattern type    | Prism class               |
|-----------------|---------------------------|
| `call`          | `Prism::CallNode`         |
| `string`        | `Prism::StringNode`       |
| `integer`       | `Prism::IntegerNode`      |
| `if`            | `Prism::IfNode`           |
| `def`           | `Prism::DefNode`          |
| `constant_read` | `Prism::ConstantReadNode` |

A bare node type matches any node of that type:

```
call          # matches any CallNode
def           # matches any DefNode
```

### Attribute Matching

Curly braces after the node type specify **attribute constraints**. Attributes
correspond to Prism node accessor methods:

```
call{name=log}              # CallNode where name == :log
def{name=initialize}        # DefNode where name == :initialize
constant_read{name=Logger}  # ConstantReadNode where name == :Logger
```

Multiple attributes are separated by commas (AND logic):

```
call{name=info, receiver=call{name=logger}}
```

### Attribute Values

**Symbol/string values** are unquoted. The value is matched against the node attribute
after calling `.to_s` on both sides:

```
call{name=log}       # matches when node.name.to_s == "log"
```

**Method names** that end in `?`, `!` or `=` are written as they are, and so are
operator methods:

```
call{name=valid?}          # record.valid?
call{name=strip_sources!}  # strip_sources!
call{name=value=}          # record.value = 1
call{name=<=>}             # a <=> b
call{name=-@}              # -a (unary minus)
```

The bare operators are `<=>`, `===`, `==`, `=~`, `[]=`, `[]`, `<=`, `<<`, `<`,
`>=`, `>>`, `>`, `+@`, `-@`, `+`, `-`, `/`, `%`, `&`, `^` and `~`. Any other
name — `|`, `!`, `!=`, `!~`, `*`, `**`, a backtick — goes in single or double
quotes, since unquoted these characters mean alternation, negation or a wildcard.
A quoted name is matched literally:

```
call{name='|'}       # a | b, not an alternation
call{name='*'}       # a * b, not a wildcard
call{name='!='}      # a != b, not a negation
```

**Alternatives** use `|` (OR logic) within a single attribute value:

```
call{name=debug|info|warn|error|fatal}   # matches any log level
call{name=puts|p|pp|print}               # matches common debug output
```

**Wildcard** `*` matches any value (useful for requiring an attribute exists):

```
call{receiver=*}     # matches any call with a receiver (not bare function calls)
```

### Nested Patterns

Attribute values can be **nested patterns**, enabling structural matching:

```
call{receiver=call{name=logger}}
# Matches: logger.info("msg"), logger.debug(data)
# Does NOT match: info("msg"), foo.info("msg")
```

Nesting can go arbitrarily deep:

```
call{receiver=call{receiver=constant_read{name=Rails}, name=logger}}
# Matches: Rails.logger.info("msg")
```

### Wildcards

The `_` pattern matches **any single node**:

```
call{receiver=_}     # any call with any receiver
call{name=log, receiver=_}  # .log() called on anything
```

The `**` pattern matches **any subtree** (zero or more levels):

```
call{receiver=**, name=log}
# Matches: log(), foo.log(), foo.bar.log(), a.b.c.log()
```

### Negation

Prefix `!` negates a pattern or value:

```
call{receiver=call{name=logger}, name=!error}  # logger calls except logger.error
call{name=info, receiver=!call{name=logger}}   # info calls not sent to logger
```

Keep a negation inside a pattern that is narrow without it. A pattern ignores
every mutation inside the nodes it matches (see
[Pattern Matching Semantics](#pattern-matching-semantics)), so a negation that
leaves the pattern broad ignores almost everything: `call{name=!log}` matches
nearly every call, and with it every mutation of their receivers, arguments and
blocks.

## YAML Configuration

```yaml
ignore_patterns:
  # Suppress mutations on all logging calls
  - "call{name=debug|info|warn|error|fatal, receiver=call{name=logger}}"

  # Suppress mutations on debug output
  - "call{name=puts|p|pp|print}"

  # Suppress mutations on Rails logger at any depth
  - "call{receiver=call{receiver=constant_read{name=Rails}, name=logger}}"

  # Suppress mutations inside any method named `to_s`
  - "def{name=to_s}"

  # Suppress mutations on constant `ENV` reads
  - "call{receiver=constant_read{name=ENV}}"

  # Suppress mutations on bang and predicate calls, and on `<=>`
  - "call{name=strip_sources!|eager_load!|valid?}"
  - "call{name=<=>}"

  # Quote names made of reserved characters
  - "call{name='|'}"
```

## Pattern Matching Semantics

1. Each pattern is tested against the **mutation's AST node** and its **ancestors**,
   up to the top of the file. A pattern naming a node therefore ignores every
   mutation inside it: `call{name=validates}` ignores the mutations of the
   literals in `validates :rush, inclusion: { in: [false, true] }, if: :paid`,
   and `keyword_hash` ignores those of the options but not of `:rush`. A `call`
   pattern covers the whole call — its receiver, its arguments and its block — so
   `call{name=on}` on `opts.on("-j", Integer) { |n| @jobs = n > 0 ? n : 1 }`
   ignores the mutations of the handler block as well. There is no form that
   matches the mutated node alone; to leave a call's block mutated, put
   `# evilution:disable` at the end of the call's line and start the block's
   body on the next line (`do |n|` … `end`).
2. A mutation is ignored if **any** pattern in `ignore_patterns` matches. Only
   mutations the run would otherwise make are counted as skipped: those in the
   requested line ranges, each counted once however many patterns, nodes or
   operators produce it, and not one that the run makes anyway from a node no
   pattern matches.
3. `def` patterns follow from rule 1: the method a mutation sits in is one of its
   ancestors, so `def{name=to_s}` ignores all mutations within `to_s`. A `class`
   or `module` pattern ignores all mutations within that body the same way.
4. Attribute matching is **exact** (after `.to_s` coercion) unless alternatives (`|`)
   or wildcards (`*`, `_`, `**`) are used.
5. Unspecified attributes are unconstrained (implicit wildcard).

## Grammar (EBNF)

```ebnf
pattern        = node_type [ "{" attributes "}" ]
node_type      = identifier | "_" | "**"
attributes     = attribute { "," attribute }
attribute      = identifier "=" value
value          = "!" value
               | nested_pattern
               | alternatives
               | "*"
nested_pattern = node_type "{" attributes "}"
alternatives   = atom { "|" atom }
atom           = name | "*"
name           = identifier [ "?" | "!" | "=" ]
               | operator
               | "'" { any character except "'" } "'"
               | '"' { any character except '"' } '"'
operator       = "<=>" | "===" | "==" | "=~" | "[]=" | "[]" | "<=" | "<<" | "<"
               | ">=" | ">>" | ">" | "+@" | "-@" | "+" | "-" | "/" | "%"
               | "&" | "^" | "~"
identifier     = [a-zA-Z_] [a-zA-Z0-9_]*
```

A bare `name` without `{` is parsed as a scalar value (matched via `.to_s`).
An `identifier` followed by `{` is parsed as a nested pattern. Operators are
read longest first, so `<=>` is never taken for `<=`. Node types and attribute
names are always plain identifiers. A quoted name is at least one character long.

## Examples

| Pattern | Matches | Does NOT match |
|---------|---------|----------------|
| `call` | Any method call | Literals, assignments |
| `call{name=log}` | `log()`, `x.log()` | `logger()`, `x.debug()` |
| `call{name=debug\|info}` | `debug()`, `x.info()` | `warn()`, `error()` |
| `call{receiver=call{name=logger}}` | `logger.info()` | `info()`, `foo.info()` |
| `call{receiver=_}` | `x.foo()`, `obj.bar()` | `foo()` (no receiver) |
| `call{receiver=**}` | `foo()`, `x.foo()`, `a.b.foo()` | *(matches all)* |
| `def{name=to_s}` | `def to_s; ... end` | `def to_str; ... end` |
| `call{receiver=call{name=logger}, name=!error}` | `logger.info()`, `logger.debug()` | `logger.error()`, `info()` |
| `call{name=valid?\|save!}` | `x.valid?`, `save!` | `valid`, `save` |
| `call{name=<=>}` | `a <=> b` | `a <= b` |
| `call{name='\|'}` | `a \| b` | `a & b` |

## Design Decisions

1. **Prism-native naming**: Node types map directly to Prism class names (lowercased,
   `Node` suffix stripped). No abstraction layer — users who inspect AST output can
   write patterns immediately.

2. **Unquoted values**: Attribute values don't require quotes. This keeps YAML clean
   and avoids escaping issues. Method names ending in `?`, `!` or `=` and operators
   that cannot be confused with pattern syntax are written bare too. Only names
   built from reserved characters (`|`, `!`, `*`) or characters outside a method
   name need quotes; there is no escaping inside them. In YAML, use one kind of
   quote for the YAML string and the other inside it: `- "call{name='|'}"`.

3. **Implicit wildcards for unspecified attributes**: `call{name=log}` matches
   regardless of receiver, arguments, etc. Only specified attributes constrain the
   match.

4. **OR within attributes, AND across attributes**: `name=a|b` is OR;
   `name=a, receiver=x` is AND. This covers the common cases without needing
   explicit boolean operators.

5. **`**` for deep matching**: Inspired by glob syntax. Enables "match .log() at any
   call depth" without enumerating receiver chains.

6. **No regex support**: Exact match + alternatives covers the practical use cases.
   Regex would complicate parsing and make patterns harder to read. Can be added later
   if needed.
