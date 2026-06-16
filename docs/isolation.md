# Isolation strategies

Evilution runs every mutant inside an isolated environment so a misbehaving
mutant cannot corrupt the runner's state or the surrounding test suite. The
`--isolation` flag (and the `isolation:` config key) selects which strategy
is used.

## Strategies

| Strategy     | What it does                                                           | When to use                                                |
| ------------ | ---------------------------------------------------------------------- | ---------------------------------------------------------- |
| `auto`       | Default. Picks `fork` for Rails projects and packaged gems, `in_process` otherwise. | Leave this on unless you have a specific reason to change. |
| `fork`       | Forks a fresh child process per mutant. Parent `SIGKILL`s on timeout.  | Rails / ActiveRecord projects; any code that uses mutexes, monitors, or async-interrupt masks. |
| `in_process` | Runs the mutant inside the runner process under `Timeout.timeout`.     | Pure-Ruby libraries that do not use async-interrupt masks. |

## Why fork is the default for Rails projects

Rails wraps every ActiveRecord transaction in
`Thread.handle_interrupt(Exception => :never)` to guarantee that a transaction
either commits cleanly or rolls back cleanly — it must never exit the
transaction block with a half-delivered exception. The mask is
[load-bearing for transaction correctness][rails-handle-interrupt].

That mask interacts badly with `Timeout.timeout`. The Timeout gem schedules a
timer thread which fires `Thread#raise Timeout::Error` at the main thread when
the deadline hits. Ruby receives the `raise`, inspects the interrupt mask, sees
`Exception => :never`, and **queues the exception for later delivery** — "later"
meaning "when the masked block exits". If the mutant is stuck in an infinite
loop inside the transaction, the block never exits, the queued exception is
never delivered, and the runner hangs indefinitely.

This is not a bug in Timeout or in Rails. Each component is correct in
isolation. They simply do not compose for in-process timeout-based
cancellation. The only primitive that can escape a masked-interrupt section
in the same thread is an out-of-band kernel signal — `SIGKILL` from another
process. That is exactly what the `fork` strategy provides.

Because of this, `auto` resolves to `fork` whenever the target files live
under a detected Rails root (i.e. a directory containing
`config/application.rb`). If you explicitly pass `--isolation in_process` on
a Rails project, evilution emits a warning naming the hazard and proceeds
anyway — sometimes you know the code under test never enters a masked
section, and that is your call to make.

`auto` also resolves to `fork` when the target files live under a packaged
gem (a directory containing a `*.gemspec`). A gem's library and test
framework must be loaded in the parent before forking — see [Automatic
preload](#automatic-preload) — and `in_process` cannot preload them without
polluting the host process. A non-Rails gem run under the old `in_process`
default therefore produced 0 examples / 100% errors out of the box; defaulting
gems to `fork` lets auto-preload fire (EV-z03y, PR #1375). A plain non-Rails,
non-gem project (no gemspec) still defaults to `in_process`.

The same hazard applies to any Ruby code that uses
`Thread.handle_interrupt(... => :never)`: `Mutex#synchronize`, `Monitor#synchronize`,
`Queue`, `ActiveSupport::Notifications::Fanout` listeners, and custom cleanup
blocks that wrap "must complete" sections. If your target code can touch any
of those, prefer `--isolation fork`.

## Parent-process preload

Fork isolation's one downside is that every child pays the cost of loading
its test framework from scratch. For a Rails app, that is 5–15 seconds of
`require "rails/all"` per mutant — multiplied by hundreds of mutants, the
run takes hours.

To avoid that cost, evilution preloads a bootstrap file in the **parent**
process before the mutation loop begins. Once Rails is loaded in the parent,
every forked child inherits the loaded state via copy-on-write, and the child
runs its test near-instantly against an already-loaded framework.

### Automatic preload

For Rails projects (auto-detected via `config/application.rb`), evilution
automatically looks for these files in order and preloads the first one it
finds:

1. `spec/rails_helper.rb` (RSpec)
2. `spec/spec_helper.rb` (RSpec)
3. `test/test_helper.rb` (Minitest)

For a packaged gem (auto-detected via `*.gemspec`, no Rails root), evilution
preloads the conventional test helper — which loads both the gem's library
and the suite's framework/support setup so example groups register — in this
order, falling back to the gem's library entry point (`lib/<gem>.rb`):

1. `spec/spec_helper.rb` (RSpec)
2. `test/test_helper.rb` (Minitest / Test::Unit)
3. `test/helper.rb` (flat-layout convention)

When a gem is detected but none of those helpers exist, evilution prints a
warning naming the locations it looked in and pointing at `--preload`, so a
non-standard test layout reads as a fixable configuration issue rather than a
silent 0% (EV-z03y, PR #1375).

Minitest/Test::Unit helpers that `require "test_helper"` (or any non-relative
`require "support/..."`) work without `-Itest`: evilution puts the test root
on `$LOAD_PATH` for the preload just as the test runner would (EV-5hk5, PR
#1373).

No configuration needed.

### Explicit preload

Override the auto-detected path with the `--preload` flag or the `preload:`
config key:

```bash
bundle exec evilution run app/models/user.rb --preload config/evilution_boot.rb
```

```yaml
# .evilution.yml
preload: config/evilution_boot.rb
```

The path is resolved relative to the working directory. Preload failures
(the file does not exist, or it raises during `require`) are fatal —
evilution aborts with an `Evilution::ConfigError` that includes the original
exception.

### Disabling preload

Pass `--no-preload` on the CLI or set `preload: false` in `.evilution.yml`:

```bash
bundle exec evilution run app/models/user.rb --no-preload
```

The MCP tool (`evilution-mutate`) disables preload unconditionally, because
the MCP server is a long-lived process that handles runs from different
projects — preloading one project's Rails stack into a shared process would
poison subsequent runs.

## Sandboxed working directory

Every isolator runs `test_command.call` inside a per-mutation scratch
directory (`Dir.mktmpdir("evilution-run")`) that is removed on the way out.
Mutations that turn an absolute path into a relative one — for example
`argument_removal` on `File.join(dir, name)` collapsing to `File.write(name,
…)` — would otherwise drop files into the parent process's CWD (typically
the repo root) and leak past the run.

Project-relative paths used by `SpecResolver`, `SpecSelector`, the
`RSpec::Core::Runner` / `Minitest.load` invocation sites, and the mutated
file's `__FILE__` in `SourceEvaluator` are anchored at
`Evilution::PROJECT_ROOT` (captured at load time), so the sandbox CWD does
not break spec lookup or `require_relative` chains inside the mutant.

## Proof-of-life canary

Before any real mutation runs, `Evilution::Runner::Canary` evals a
synthetic, guaranteed-unobservable mutation through the configured
integration + isolation. A healthy pipeline must score it `:survived`; any
other status aborts the run with a diagnostic so the user never sees a
score produced by a broken pipeline (autoload mismatch, reporter-plugin
eviction, isolation defect, `fail_if_no_examples` config drift, etc.).
On by default; toggle with `--[no-]canary` or `canary: true|false` in
`.evilution.yml`. The canary mirrors the configured `--isolation` so
isolation-specific defects are caught too.

## Parallel run resilience (`--jobs N`)

Under `--jobs N` a stuck or crashed worker no longer takes the whole run down.
The work-queue dispatcher tracks a per-worker deadline: if one mutation blocks
past its timeout (e.g. a mutation that wedges a child in `ConditionVariable#wait`)
or a worker exits unexpectedly, only that worker is killed and recycled, its
single in-flight mutation is recorded as `:timeout` / `:error`, and the run
continues with the remaining work. A single pathological mutation costs you one
result, not the entire run.

Each worker is also its own process-group leader, so killing a worker reaps the
mutation subprocess and any grandchildren it spawned rather than orphaning them,
and a terminal interrupt (Ctrl-C) is forwarded to every worker group — an
aborted parallel run leaves no stray worker or mutation processes behind.

## Related flags

- `--timeout N` sets the per-mutation time limit. Under `fork`, this drives
  SIGKILL. Under `in_process`, this drives `Timeout.timeout` and is subject
  to the interrupt-mask hazard described above.
- `--jobs N` runs N workers in parallel. The parallel pool respects the
  configured isolation strategy, so `--jobs 4 --isolation fork` uses fork
  isolation per-mutation inside each worker.
- `--[no-]canary` toggles the proof-of-life pre-flight check (see above).

[rails-handle-interrupt]: https://github.com/rails/rails/blob/main/activesupport/lib/active_support/concurrency/thread_monitor.rb
