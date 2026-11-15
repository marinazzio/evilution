# frozen_string_literal: true

require_relative "../actions"
require_relative "base"
require_relative "../../../config"
require_relative "../../../version"

class Evilution::MCP::InfoTool::Actions::Environment < Evilution::MCP::InfoTool::Actions::Base
  # The config readers reported under "settings", each under its own name.
  SETTINGS = %w[
    timeout format integration jobs isolation baseline incremental fail_fast stop_on_kill killer_first
    skip_uncovered probe_first min_score suggest_tests save_session target skip_heredoc_literals ignore_patterns
  ].freeze
  private_constant :SETTINGS

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
      SETTINGS.to_h { |name| [name, config.public_send(name)] }
    end
  end
end
