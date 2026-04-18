# frozen_string_literal: true

require "json"
require_relative "../mutate_tool"

module Evilution::MCP::MutateTool::ReportTrimmer
  MINIMAL_KEYS = %w[summary survived].freeze
  FULL_DIFF_STRIP_KEYS = %w[killed neutral equivalent unresolved].freeze
  SUMMARY_DROP_KEYS = %w[killed neutral equivalent].freeze

  def self.call(json_string, verbosity:, survived_results:, config:, enricher:)
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
    ::JSON.generate(data)
  end

  def self.strip_diffs(data, key)
    return unless data[key]

    data[key].each { |entry| entry.delete("diff") }
  end
  private_class_method :strip_diffs
end
