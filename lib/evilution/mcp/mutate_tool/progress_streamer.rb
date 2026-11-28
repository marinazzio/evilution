# frozen_string_literal: true

require "json"
require_relative "../mutate_tool"
require_relative "../../reporter/suggestion"
require_relative "../../diagnostic"
require_relative "../../encoding_normalizer"

module Evilution::MCP::MutateTool::ProgressStreamer
  # Retags BINARY strings and scrubs invalid UTF-8 so JSON generation cannot fail on them.
  ENCODING_NORMALIZER = Evilution::EncodingNormalizer.new

  def self.build(server_context:, suggest_tests:, integration:)
    return nil unless suggest_tests && server_context.respond_to?(:report_progress)

    suggestion = Evilution::Reporter::Suggestion.new(suggest_tests: true, integration: integration)
    survivor_index = 0
    disabled = false

    proc do |result|
      next unless result.survived? || result.uncovered?
      next if disabled

      begin
        survivor_index += 1
        detail = build_suggestion_detail(result.mutation, suggestion)
        server_context.report_progress(survivor_index, message: ::JSON.generate(ENCODING_NORMALIZER.call(detail)))
      rescue StandardError => e
        Evilution::Diagnostic.warn("[evilution] progress stream disabled after error: #{e.class}: #{e.message}")
        disabled = true
      end
    end
  end

  def self.build_suggestion_detail(mutation, suggestion)
    {
      operator: mutation.operator_name,
      file: mutation.file_path,
      line: mutation.line,
      subject: mutation.subject.name,
      diff: mutation.diff,
      suggestion: suggestion.suggestion_for(mutation)
    }
  end
  private_class_method :build_suggestion_detail
end
