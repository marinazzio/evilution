# frozen_string_literal: true

require "open3"
require_relative "run_result"

# Runs a command in a directory and returns [stdout, stderr, success].
# Strips the harness's own bundler environment: when this script runs under
# `bundle exec`, Bundler exports BUNDLE_GEMFILE/RUBYOPT, which would make the
# inner bundle resolve against evilution's Gemfile instead of the target's.
class BenchmarkPerf::CommandRunner
  def call(cmd, dir:, env: {})
    stdout, stderr, status =
      if defined?(Bundler)
        Bundler.with_unbundled_env { Open3.capture3(env, *cmd, chdir: dir) }
      else
        Open3.capture3(env, *cmd, chdir: dir)
      end
    [stdout, stderr, status.success?]
  end
end
