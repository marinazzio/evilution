# Test Framework Integrations

Evilution supports three test framework integrations, selected via the
`--integration NAME` CLI flag (or the `integration:` key in `.evilution.yml`).
Each integration owns its own framework loader, dispatcher, spec resolver,
and result builder so they can evolve independently.

| Integration   | Flag value    | Default test dir | Default test suffix | Gem dep                |
|---------------|---------------|------------------|---------------------|------------------------|
| RSpec         | `rspec`       | `spec/`          | `_spec.rb`          | `rspec-core`           |
| Minitest      | `minitest`    | `test/`          | `_test.rb`          | `minitest`             |
| Test::Unit    | `test-unit`   | `test/`          | `_test.rb`          | `test-unit`            |

## When to pick which

- **`rspec`** (default) — Suites built on `RSpec.describe` / `it` / `expect`.
- **`minitest`** — Suites that subclass `Minitest::Test` or use
  `Minitest::Spec`'s `describe` / `it`. Includes Rails apps where
  `ActiveSupport::TestCase` inherits from `Minitest::Test`.
- **`test-unit`** — Suites that subclass `Test::Unit::TestCase`, including
  Rails projects that `require "test/unit/rails/test_help"` (which makes
  `ActiveSupport::TestCase < Test::Unit::TestCase`). The `test-unit` gem's
  `TestCase` classes are *not* `Minitest::Runnable` subclasses, so the
  `minitest` integration cannot dispatch them — pick this integration whenever
  your test helper pulls in `test/unit/rails/test_help`, `test-unit-activerecord`,
  or similar test-unit-specific glue.

## CLI examples

```bash
# RSpec — default; specs in spec/, named *_spec.rb
bundle exec evilution run lib/foo.rb

# Minitest
bundle exec evilution run lib/foo.rb \
  --integration minitest --spec test/foo_test.rb

# Test::Unit (gem name uses hyphen; symbol value uses underscore)
bundle exec evilution run lib/foo.rb \
  --integration test-unit --spec test/foo_test.rb
```

The CLI accepts both `test-unit` and `test_unit` strings; the internal config
symbol is always `:test_unit`.

## MCP examples

The `evilution-mutate` MCP tool exposes `integration` as a JSON schema enum
of `["rspec", "minitest", "test-unit"]`:

```json
{
  "tool": "evilution-mutate",
  "args": {
    "files": ["lib/foo.rb"],
    "integration": "test-unit",
    "spec": ["test/foo_test.rb"]
  }
}
```

## Spec resolution conventions

When `--spec` is not supplied, evilution resolves a test file from the source
path using the integration's spec resolver. Strips `lib/` or `app/` prefix
and rewrites the suffix:

| Source                              | rspec                               | minitest / test-unit               |
|-------------------------------------|-------------------------------------|------------------------------------|
| `lib/foo.rb`                        | `spec/foo_spec.rb`                  | `test/foo_test.rb`                 |
| `lib/foo/bar.rb`                    | `spec/foo/bar_spec.rb`              | `test/foo/bar_test.rb`             |
| `app/models/user.rb`                | `spec/models/user_spec.rb`          | `test/models/user_test.rb`         |
| `app/controllers/users_controller.rb` | `spec/requests/users_spec.rb` *or* `spec/controllers/users_controller_spec.rb` | `test/integration/users_test.rb` *or* `test/controllers/users_controller_test.rb` |

For controllers, the resolver tries the request-spec / integration-test
location first, then falls back to the controller-spec / controller-test
location.

## Suggest-tests caveat

The `--suggest-tests` mode emits ready-to-paste test snippets for survived
mutations. Concrete templates currently exist for **rspec** and **minitest**
only; the **test-unit** integration falls back to the generic operator-level
suggestion text. Adding test-unit templates is a small follow-up.

## Other Ruby test frameworks

No additional integrations are planned at the moment. The three integrations
above cover the overwhelming majority of Ruby projects with unit / integration
test suites. Frameworks we considered and deferred:

- **Cucumber / Spinach** — BDD scenarios over Gherkin step definitions, a
  fundamentally coarser granularity than mutation testing rewards. Not a
  natural fit; no plans to add.
- **Sus** — Socketry's async-focused framework, small but actively maintained
  user base. Could be added under the same orchestrator/collaborator pattern
  if a real project surfaces needing it.
- **Bacon, Test::Spec** — early RSpec-style clones, effectively dormant.
- **Minitest::Spec** — already covered by the `minitest` integration.

If you maintain a project on another framework and would benefit from
mutation-testing it through evilution, open an issue describing the project
and the framework's dispatch entry-point — the existing integration layout
makes new entries cheap to add.

## Behind the scenes

Each integration has an orchestrator class at
`lib/evilution/integration/<name>.rb`. RSpec and Test::Unit additionally
decompose their collaborators into a sibling directory of the same name
(`lib/evilution/integration/rspec/...`,
`lib/evilution/integration/test_unit/...`); Minitest remains a single file.
The test-unit collaborators are:

- `framework_loader.rb` — `require "test-unit"` + disables the at_exit
  auto-run handler so it doesn't fire on evilution exit.
- `subject_class_registry.rb` — ObjectSpace tracking of newly-loaded
  `Test::Unit::TestCase` subclasses (test-unit has no public
  registry-clear analog to `Minitest::Runnable.runnables`).
- `dispatcher.rb` — assembles a `Test::Unit::TestSuite` from the new
  classes and runs it via `Test::Unit::UI::Console::TestRunner` with
  output captured to a `StringIO`.
- `test_file_resolver.rb` — explicit-override + spec-selector +
  fallback glob + warn-once for unresolved sources.
- `result_builder.rb` — shapes the `passed`/`test_crashed`/
  `no_tests_ran`/`unresolved` Hash that flows into `classify_status`.
