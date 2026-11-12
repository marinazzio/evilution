# frozen_string_literal: true

require "erb"
require "yaml"
require_relative "version"

# EV-kdns / GH #817: nudge users running parallel jobs against SQLite to adopt
# the parallel_tests convention. WorkQueue sets TEST_ENV_NUMBER per worker, but
# that only helps if config/database.yml interpolates it into the database path,
# so the warning fires only when the test database path does not depend on it.
# Without per-worker DB files, concurrent workers pile up on one SQLite file and
# surface ActiveRecord::StatementTimeout / SQLite3::BusyException — noise that
# MutationExecutor demotes to :neutral but still wastes wall-clock time.
module Evilution::ParallelDbWarning
  DATABASE_YML = File.join("config", "database.yml")
  MESSAGE = "[evilution] Parallel run (jobs > 1) detected with SQLite in " \
            "config/database.yml. Interpolate ENV['TEST_ENV_NUMBER'] into the " \
            "test database path for per-worker DB isolation. See README."

  @warned_roots = {}
  @mutex = Mutex.new

  class << self
    def warn_if_sqlite_parallel(config, output: $stderr, root: Dir.pwd)
      return unless config.jobs > 1
      return unless shared_sqlite_test_database?(root)

      @mutex.synchronize do
        return if @warned_roots[root]

        @warned_roots[root] = true
      end

      output.puts(MESSAGE)
    end

    def reset!
      @mutex.synchronize { @warned_roots.clear }
    end

    private

    # Only the `test` section matters for parallel mutation runs. Scanning the
    # whole file would false-positive when dev/prod use SQLite but test uses
    # Postgres/MySQL. The file is rendered for two workers; if the test section
    # comes out the same, every worker shares one database file. Parse failures
    # (ERB errors, custom helpers, anchor gymnastics) fall back to "no warning"
    # rather than guessing.
    def shared_sqlite_test_database?(root)
      path = File.join(root, DATABASE_YML)
      return false unless File.exist?(path)

      content = File.read(path)
      first_worker = test_section(content, "")
      return false unless sqlite?(first_worker)

      first_worker == test_section(content, "2")
    end

    def sqlite?(test_config)
      return false unless test_config.is_a?(Hash)

      adapter = test_config["adapter"]
      adapter.is_a?(String) && adapter.downcase.include?("sqlite")
    end

    def test_section(content, test_env_number)
      parsed = YAML.safe_load(render(content, test_env_number), aliases: true)
      parsed["test"] if parsed.is_a?(Hash)
    rescue StandardError, SyntaxError
      nil
    end

    # Renders the ERB against a copy of ENV with TEST_ENV_NUMBER set, so the
    # process environment is never touched: ENV inside the template resolves
    # to the scope's own constant before the global one.
    def render(content, test_env_number)
      scope = Module.new
      scope.const_set(:ENV, ENV.to_h.merge("TEST_ENV_NUMBER" => test_env_number))
      ERB.new(content).result(scope.module_eval("binding", __FILE__, __LINE__))
    end
  end
end
