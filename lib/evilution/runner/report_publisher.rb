# frozen_string_literal: true

require_relative "../runner"
require_relative "../reporter/json"
require_relative "../reporter/cli"
require_relative "../reporter/html"
require_relative "../session/store"

class Evilution::Runner::ReportPublisher
  def initialize(config)
    @config = config
  end

  def publish(summary, stdout: $stdout)
    reporter = build_reporter
    return unless reporter

    output = reporter.call(summary)
    return if config.quiet

    deliver(output, stdout)
  end

  def deliver(output, stdout)
    return publish_html(output) if config.html?
    return File.write(config.output, output) if config.output

    stdout.puts(output)
    claim_stdout(stdout) if config.json?
  end

  # `--preload` brings the project's at_exit hooks into this process, and
  # SimpleCov's prints its coverage report on the way out. Once the document is
  # written, stdout is pointed at stderr so nothing can append to it and leave a
  # consumer with unparseable JSON (EV-g8ya / GH #1608). Text reports are read
  # by people, not parsers, so they keep the stream as it was.
  def claim_stdout(stdout)
    stdout.flush
    stdout.reopen($stderr)
  rescue TypeError
    # A harness that captures output swaps $stdout for a StringIO, which cannot
    # be reopened onto an IO. There is no file descriptor to protect there.
    nil
  end

  def publish_html(output)
    path = "evilution-report.html"
    File.write(path, output)
    warn "HTML report written to #{path}"
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
      Evilution::Reporter::CLI.new(min_score: config.min_score)
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
