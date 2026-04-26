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

  def self.call(json_string, verbosity:, survived_results:, config:, enricher:, summary: nil)
    data = ::JSON.parse(json_string)
    case verbosity
    when "full"
      FULL_DIFF_STRIP_KEYS.each { |key| strip_diffs(data, key) }
    when "summary"
      SUMMARY_DROP_KEYS.each { |key| data.delete(key) }
    when "minimal"
      data.keep_if { |key, _| MINIMAL_KEYS.include?(key) }
    end
    enricher.call(data, survived_results, config)
    embed_feedback(data, summary)
    ::JSON.generate(data)
  end

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
