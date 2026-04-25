# frozen_string_literal: true

require_relative "base"
require_relative "../config_factory"
require_relative "../../../runner"
require_relative "../../../mutator/registry"
require_relative "../../../ast/pattern/filter"

class Evilution::MCP::InfoTool::Actions::Subjects < Evilution::MCP::InfoTool::Actions::Base
  def self.call(files: nil, line_ranges: nil, target: nil, integration: nil, skip_config: nil, **)
    return config_error("files is required") if files.nil? || files.empty?

    config = Evilution::MCP::InfoTool::ConfigFactory.subjects(
      files: files, line_ranges: line_ranges,
      target: target, integration: integration, skip_config: skip_config
    )
    runner = Evilution::Runner.new(config: config)
    subjects = runner.parse_and_filter_subjects

    registry = Evilution::Mutator::Registry.default
    filter = build_subject_filter(config)
    operator_options = { skip_heredoc_literals: config.skip_heredoc_literals? }

    entries = subjects.map do |subj|
      count = registry.mutations_for(subj, filter: filter, operator_options: operator_options).length
      { "name" => subj.name, "file" => subj.file_path, "line" => subj.line_number, "mutations" => count }
    ensure
      subj.release_node!
    end

    success(
      "subjects" => entries,
      "total_subjects" => entries.length,
      "total_mutations" => entries.sum { |e| e["mutations"] }
    )
  end

  class << self
    private

    def build_subject_filter(config)
      return nil if config.ignore_patterns.empty?

      Evilution::AST::Pattern::Filter.new(config.ignore_patterns)
    end
  end
end
