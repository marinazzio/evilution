# frozen_string_literal: true

require_relative "../evilution"

# EV-kdns / GH #817: nudge users running parallel jobs against SQLite to adopt
# the parallel_tests convention. WorkQueue sets TEST_ENV_NUMBER per worker, but
# that only helps if config/database.yml interpolates it into the database path.
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
      return unless sqlite_in_database_yml?(root)

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

    def sqlite_in_database_yml?(root)
      path = File.join(root, DATABASE_YML)
      return false unless File.exist?(path)

      File.read(path).include?("sqlite3")
    end
  end
end
