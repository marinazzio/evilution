# frozen_string_literal: true

require "json"
require_relative "../mutate_tool"
require_relative "../../reporter/suggestion"

module Evilution::MCP::MutateTool::ProgressStreamer
  def self.build(server_context:, suggest_tests:, integration:)
    return nil unless suggest_tests && server_context.respond_to?(:report_progress)

    suggestion = Evilution::Reporter::Suggestion.new(suggest_tests: true, integration: integration)
    survivor_index = 0

    proc do |result|
      next unless result.survived?

      begin
        survivor_index += 1
        detail = build_suggestion_detail(result.mutation, suggestion)
        server_context.report_progress(survivor_index, message: ::JSON.generate(detail))
      rescue StandardError # rubocop:disable Lint/SuppressedException
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
