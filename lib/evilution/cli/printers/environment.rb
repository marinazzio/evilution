# frozen_string_literal: true

require_relative "../printers"

class Evilution::CLI::Printers::Environment
  PLAIN_SETTINGS = %i[
    timeout format integration jobs isolation baseline incremental
    verbose quiet progress min_score suggest_tests save_session
    skip_heredoc_literals
  ].freeze
  RUN_SETTINGS = %i[killer_first skip_uncovered probe_first copy_worker_databases].freeze

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
    plain_lines = plain_setting_lines
    plain_lines.insert(10, setting_line(:fail_fast, @config.fail_fast || "(disabled)"))
    plain_lines.insert(11, setting_line(:stop_on_kill, @config.stop_on_kill))
    plain_lines.insert(15, setting_line(:target, @config.target || "(all files)"))
    plain_lines.concat(run_lines)
    plain_lines.concat(skip_lines)
  end

  def plain_setting_lines
    PLAIN_SETTINGS.map { |k| setting_line(k, k == :timeout ? timeout_value : @config.public_send(k)) }
  end

  def run_lines
    RUN_SETTINGS.map { |k| setting_line(k, @config.public_send(k)) }
  end

  # With no timeout set, the configured one is only the fallback: each
  # mutation's limit follows the baseline time of its spec files.
  def timeout_value
    return @config.timeout unless @config.adaptive_timeout?

    "adaptive (#{@config.timeout_factor} x baseline, #{@config.timeout_floor}-#{@config.timeout_ceiling} s; " \
      "#{@config.timeout} s without a baseline time)"
  end

  def skip_lines
    [
      setting_line(:ignore_patterns, format_ignore_patterns(@config.ignore_patterns)),
      setting_line(:skip_sites, format_skip_sites(@config.skip_sites))
    ]
  end

  def setting_line(key, value)
    "  #{key}: #{value}"
  end

  def format_ignore_patterns(patterns)
    patterns.empty? ? "(none)" : patterns.inspect
  end

  def format_skip_sites(presets)
    presets.empty? ? "(none)" : presets.join(", ")
  end
end
