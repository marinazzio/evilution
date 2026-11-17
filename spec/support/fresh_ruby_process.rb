# frozen_string_literal: true

require "open3"
require "rbconfig"

module FreshRubyProcess
  LIB_DIR = File.expand_path("../../lib", __dir__)

  # Runs the script in a new Ruby that has the suite's load path but neither
  # Bundler nor the RUBYOPT the suite inherited. Bundler evaluates the
  # gemspec, which loads version.rb and so defines Evilution before the
  # script runs; that hides a file that uses the namespace without requiring
  # what defines it. Bundler gets in through RUBYOPT (-rbundler/setup), and
  # RubyGems itself requires BUNDLER_SETUP, which `bundle exec` exports.
  # An inherited RUBYOPT could also carry -W, whose warnings would land on
  # stderr. The suite's load path makes the child resolve the same gem
  # versions the suite runs with.
  def run_in_fresh_ruby(script)
    env = {
      "RUBYOPT" => nil, "BUNDLER_SETUP" => nil, "RUBYGEMS_GEMDEPS" => nil,
      "RUBYLIB" => $LOAD_PATH.join(File::PATH_SEPARATOR)
    }
    Open3.capture3(env, RbConfig.ruby, "-I", LIB_DIR, "-e", script)
  end

  # Reports whether Evilution was defined before the feature was required,
  # then the name of the constant the feature defines.
  def require_in_fresh_ruby(feature, constant)
    run_in_fresh_ruby("print defined?(Evilution).inspect, ' '; require #{feature.dump}; print #{constant}.name")
  end
end
