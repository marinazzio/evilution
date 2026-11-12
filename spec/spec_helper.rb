# frozen_string_literal: true

require "evilution"
require "tempfile"

RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = ".rspec_status"

  # Disable RSpec exposing methods globally on `Module` and `main`
  config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  # Stress/load specs spawn many real worker processes and run for a long time.
  # They are excluded from the default run and only execute when RUN_STRESS is
  # set (via `rake stress`), mirroring the opt-in memory:check harness.
  config.filter_run_excluding(:stress) unless ENV["RUN_STRESS"] == "1"

  # Evilution mutating its own code runs these examples inside its own worker,
  # where the isolated-worker flag is up. The code under test reads that same
  # flag, so an example that inherited it would resolve project-relative paths
  # against the evilution checkout instead of its own CWD and fail whatever the
  # mutation, reporting every mutant killed. Each example starts with the flag
  # down, as in a plain rspec run, and the worker gets its own back afterwards.
  config.around do |example|
    host_flag = Evilution.instance_variable_get(:@in_isolated_worker)
    Evilution.instance_variable_set(:@in_isolated_worker, nil)
    example.run
  ensure
    Evilution.instance_variable_set(:@in_isolated_worker, host_flag)
  end
end
