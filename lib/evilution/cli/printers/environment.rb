# frozen_string_literal: true

require_relative "../printers"

class Evilution::CLI::Printers::Environment
  PLAIN_SETTINGS = %i[
    timeout format integration jobs isolation baseline incremental
    verbose quiet progress min_score suggest_tests save_session
    skip_heredoc_literals
  ].freeze

  def initialize(config, config_file:)
    @config = config
    @config_file = config_file
  end

  def render(io)
    lines = header_lines
    lines.concat(settings_lines)
    io.puts(lines.join("\n"))
  end

  private

  def header_lines
    [
      "Evilution Environment",
      ("=" * 30),
      "",
      "evilution: #{Evilution::VERSION}",
      "ruby: #{RUBY_VERSION}",
      "config_file: #{@config_file || "(none)"}",
      "",
      "Settings:"
    ]
  end

  def settings_lines
    plain_lines = PLAIN_SETTINGS.map { |k| setting_line(k, @config.public_send(k)) }
    plain_lines.insert(10, setting_line(:fail_fast, @config.fail_fast || "(disabled)"))
    plain_lines.insert(14, setting_line(:target, @config.target || "(all files)"))
    plain_lines << setting_line(:ignore_patterns, format_ignore_patterns(@config.ignore_patterns))
    plain_lines
  end

  def setting_line(key, value)
    "  #{key}: #{value}"
  end

  def format_ignore_patterns(patterns)
    patterns.empty? ? "(none)" : patterns.inspect
  end
end
