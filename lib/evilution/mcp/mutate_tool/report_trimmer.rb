# frozen_string_literal: true

require "json"
require_relative "../mutate_tool"
require_relative "../../feedback"
require_relative "../../feedback/detector"
require_relative "../../feedback/messages"

module Evilution::MCP::MutateTool::ReportTrimmer
  MINIMAL_KEYS = %w[summary survived].freeze
  FULL_DIFF_STRIP_KEYS = %w[killed neutral equivalent unresolved unparseable].freeze
  SUMMARY_DROP_KEYS = %w[killed neutral equivalent unparseable].freeze

  # EV-t7kh / GH #1170: at minimal verbosity we surface a small sample of any
  # errored mutations so agents are not stuck in a diagnose-vs-token-cap
  # deadlock when a run is partly-broken. Bounded to keep the payload tiny.
  ERROR_SAMPLE_LIMIT = 3
  ERROR_BACKTRACE_HEAD_LINES = 5
  ERROR_SAMPLE_KEYS = %w[operator file line error_message error_class].freeze

  def self.call(json_string, verbosity:, survived_results:, config:, enricher:, summary: nil)
    data = ::JSON.parse(json_string)
    case verbosity
    when "full"
      FULL_DIFF_STRIP_KEYS.each { |key| strip_diffs(data, key) }
    when "summary"
      SUMMARY_DROP_KEYS.each { |key| data.delete(key) }
    when "minimal"
      apply_minimal(data)
    end
    enricher.call(data, survived_results, config)
    embed_feedback(data, summary) unless verbosity == "minimal"
    ::JSON.generate(data)
  end

  def self.apply_minimal(data)
    sample = error_sample(data["errors"])
    data.keep_if { |key, _| MINIMAL_KEYS.include?(key) }
    data["errors"] = sample if sample
  end
  private_class_method :apply_minimal

  def self.error_sample(entries)
    return nil unless entries.is_a?(Array) && !entries.empty?

    entries.first(ERROR_SAMPLE_LIMIT).map { |entry| trim_error_entry(entry) }
  end
  private_class_method :error_sample

  def self.trim_error_entry(entry)
    trimmed = entry.slice(*ERROR_SAMPLE_KEYS)
    backtrace = entry["error_backtrace"]
    trimmed["error_backtrace"] = backtrace.first(ERROR_BACKTRACE_HEAD_LINES) if backtrace.is_a?(Array)
    trimmed
  end
  private_class_method :trim_error_entry

  def self.strip_diffs(data, key)
    return unless data[key]

    data[key].each { |entry| entry.delete("diff") }
  end
  private_class_method :strip_diffs

  def self.embed_feedback(data, summary)
    return unless Evilution::Feedback::Detector.friction?(summary)

    data["feedback_url"]  = Evilution::Feedback::DISCUSSION_URL
    data["feedback_hint"] = Evilution::Feedback::Messages.mcp_hint
  end
  private_class_method :embed_feedback
end
