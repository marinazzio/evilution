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
  config.filter_run_excluding(:stress) unless ENV["RUN_STRESS"]
end
