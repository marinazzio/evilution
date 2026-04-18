# frozen_string_literal: true

require "json"
require_relative "../mutate_tool"

module Evilution::MCP::MutateTool::ReportTrimmer
  def self.call(json_string, verbosity:, survived_results:, config:, enricher:)
    data = ::JSON.parse(json_string)
    case verbosity
    when "full"
      strip_diffs(data, "killed")
      strip_diffs(data, "neutral")
      strip_diffs(data, "equivalent")
    when "summary"
      data.delete("killed")
      data.delete("neutral")
      data.delete("equivalent")
    when "minimal"
      data.delete("killed")
      data.delete("neutral")
      data.delete("equivalent")
      data.delete("timed_out")
      data.delete("errors")
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
