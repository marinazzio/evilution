# frozen_string_literal: true

require_relative "../printers"

class Evilution::CLI::Printers::Environment
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
    [
      "  timeout: #{@config.timeout}",
      "  format: #{@config.format}",
      "  integration: #{@config.integration}",
      "  jobs: #{@config.jobs}",
      "  isolation: #{@config.isolation}",
      "  baseline: #{@config.baseline}",
      "  incremental: #{@config.incremental}",
      "  verbose: #{@config.verbose}",
      "  quiet: #{@config.quiet}",
      "  progress: #{@config.progress}",
      "  fail_fast: #{@config.fail_fast || "(disabled)"}",
      "  min_score: #{@config.min_score}",
      "  suggest_tests: #{@config.suggest_tests}",
      "  save_session: #{@config.save_session}",
      "  target: #{@config.target || "(all files)"}",
      "  skip_heredoc_literals: #{@config.skip_heredoc_literals}",
      "  ignore_patterns: #{@config.ignore_patterns.empty? ? "(none)" : @config.ignore_patterns.inspect}"
    ]
  end
end
