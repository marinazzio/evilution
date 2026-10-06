# frozen_string_literal: true

require_relative "../baseline"

class Evilution::Baseline
  ExampleFailure = Data.define(:id, :description, :message)

  # Why one spec file was red in the baseline: the examples that failed, or the
  # error that stopped it before any example could -- a load error, a runner
  # that raised, a timeout. example_count is every failing example; examples
  # holds only the first few, for display; failed_ids names all of them the
  # way a mutation run does, for comparison.
  SpecFailure = Data.define(:spec_file, :examples, :example_count, :error, :failed_ids) do
    def self.from_report(spec_file, report)
      examples = Array(report[:failures]).map { |failure| ExampleFailure.new(**failure) }
      new(
        spec_file: spec_file,
        examples: examples,
        example_count: report[:failure_count] || examples.length,
        error: report[:error],
        failed_ids: Array(report[:failed_ids])
      )
    end

    def initialize(spec_file:, examples: [], example_count: 0, error: nil, failed_ids: [])
      super
    end

    def to_h
      {
        spec_file: spec_file,
        error: error,
        failing_examples: example_count,
        examples: examples.map(&:to_h)
      }
    end
  end
end
