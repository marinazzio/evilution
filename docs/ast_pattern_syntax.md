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
call{receiver=call{receiver=call{name=Rails}, name=logger}}
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
call{name=!log}              # any call except log
call{receiver=!call{name=logger}}  # calls whose receiver is not logger
```

## YAML Configuration

```yaml
ignore_patterns:
  # Suppress mutations on all logging calls
  - "call{name=debug|info|warn|error|fatal, receiver=call{name=logger}}"

  # Suppress mutations on debug output
  - "call{name=puts|p|pp|print}"

  # Suppress mutations on Rails logger at any depth
  - "call{receiver=call{receiver=call{name=Rails}, name=logger}}"

  # Suppress mutations inside any method named `to_s`
  - "def{name=to_s}"

  # Suppress mutations on constant `ENV` reads
  - "call{receiver=constant_read{name=ENV}}"
```

## Pattern Matching Semantics

1. Each pattern is tested against the **mutation's AST node** and its **ancestors**.
2. A mutation is ignored if **any** pattern in `ignore_patterns` matches.
3. For `def` patterns, the match is against the enclosing method node, not the
   mutated node itself. This allows ignoring all mutations within a method.
4. Attribute matching is **exact** (after `.to_s` coercion) unless alternatives (`|`)
   or wildcards (`*`, `_`, `**`) are used.
5. Unspecified attributes are unconstrained (implicit wildcard).

## Grammar (EBNF)

```ebnf
pattern     = node_type [ "{" attributes "}" ]
node_type   = identifier | "_" | "**"
attributes  = attribute { "," attribute }
attribute   = identifier "=" value
value       = "!" value
            | pattern
            | alternatives
            | "*"
alternatives = atom { "|" atom }
atom         = identifier | "*"
identifier   = [a-zA-Z_] [a-zA-Z0-9_]*
```

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
| `call{name=!log}` | `debug()`, `info()` | `log()` |

## Design Decisions

1. **Prism-native naming**: Node types map directly to Prism class names (lowercased,
   `Node` suffix stripped). No abstraction layer — users who inspect AST output can
   write patterns immediately.

2. **Unquoted values**: Attribute values don't require quotes. This keeps YAML clean
   and avoids escaping issues. The tradeoff is that values cannot contain `{`, `}`,
   `,`, `=`, `|`, or `!` — these are reserved syntax characters.

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
