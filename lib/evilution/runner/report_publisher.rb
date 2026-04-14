# frozen_string_literal: true

require_relative "../reporter/json"
require_relative "../reporter/cli"
require_relative "../reporter/html"
require_relative "../session/store"

class Evilution::Runner; end unless defined?(Evilution::Runner) # rubocop:disable Lint/EmptyClass

class Evilution::Runner::ReportPublisher
  def initialize(config)
    @config = config
  end

  def publish(summary)
    reporter = build_reporter
    return unless reporter

    output = reporter.call(summary)
    return if config.quiet

    if config.html?
      path = "evilution-report.html"
      File.write(path, output)
      warn "HTML report written to #{path}"
    else
      $stdout.puts(output)
    end
  end

  def save_session(summary)
    return unless config.save_session?

    Evilution::Session::Store.new.save(summary)
  rescue StandardError => e
    warn "[evilution] failed to save session: #{e.message}" unless config.quiet
  end

  private

  attr_reader :config

  def build_reporter
    case config.format
    when :json
      Evilution::Reporter::JSON.new(integration: config.integration)
    when :text
      Evilution::Reporter::CLI.new
    when :html
      Evilution::Reporter::HTML.new(baseline: load_baseline_session, integration: config.integration)
    end
  end

  def load_baseline_session
    path = config.baseline_session
    return nil unless path

    Evilution::Session::Store.new.load(path)
  end
end
