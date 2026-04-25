# frozen_string_literal: true

require_relative "base"
require_relative "../../../config"
require_relative "../../../version"

class Evilution::MCP::InfoTool::Actions::Environment < Evilution::MCP::InfoTool::Actions::Base
  def self.call(**)
    config = Evilution::Config.new(skip_config_file: false)
    config_file = Evilution::Config::CONFIG_FILES.find { |path| File.exist?(path) }

    success(
      "version" => Evilution::VERSION,
      "ruby" => RUBY_VERSION,
      "config_file" => config_file,
      "settings" => settings(config)
    )
  end

  class << self
    private

    def settings(config)
      {
        "timeout" => config.timeout,
        "format" => config.format,
        "integration" => config.integration,
        "jobs" => config.jobs,
        "isolation" => config.isolation,
        "baseline" => config.baseline,
        "incremental" => config.incremental,
        "fail_fast" => config.fail_fast,
        "min_score" => config.min_score,
        "suggest_tests" => config.suggest_tests,
        "save_session" => config.save_session,
        "target" => config.target,
        "skip_heredoc_literals" => config.skip_heredoc_literals,
        "ignore_patterns" => config.ignore_patterns
      }
    end
  end
end
