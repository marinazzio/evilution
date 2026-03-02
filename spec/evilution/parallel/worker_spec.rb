# frozen_string_literal: true

require "evilution/parallel/worker"

RSpec.describe Evilution::Parallel::Worker do
  subject(:worker) { described_class.new(isolator: isolator) }

  let(:isolator) { instance_double(Evilution::Isolation::Fork) }

  let(:subject_obj) do
    Evilution::Subject.new(
      name: "Example#foo",
      file_path: "lib/example.rb",
      line_number: 1,
      source: "def foo; end",
      node: nil
    )
  end

  let(:mutation) do
    Evilution::Mutation.new(
      subject: subject_obj,
      operator_name: "comparison_replacement",
      original_source: "a > b",
      mutated_source: "a < b",
      file_path: "lib/example.rb",
      line: 1
    )
  end

  let(:mutation_result) do
    Evilution::Result::MutationResult.new(
      mutation: mutation,
      status: :killed,
      duration: 0.1
    )
  end

  describe "#call" do
    it "runs each mutation through the isolator" do
      test_command = ->(_m) { { passed: false } }
      test_command_builder = ->(_mutation) { test_command }

      expect(isolator).to receive(:call).with(
        mutation: mutation,
        test_command: test_command,
        timeout: 10
      ).and_return(mutation_result)

      results = worker.call(mutations: [mutation], test_command_builder: test_command_builder, timeout: 10)

      expect(results).to eq([mutation_result])
    end

    it "returns an empty array for empty mutations" do
      results = worker.call(mutations: [], test_command_builder: ->(_m) {}, timeout: 10)

      expect(results).to eq([])
    end

    it "processes multiple mutations sequentially" do
      mutation2 = Evilution::Mutation.new(
        subject: subject_obj,
        operator_name: "nil_replacement",
        original_source: "x",
        mutated_source: "nil",
        file_path: "lib/example.rb",
        line: 2
      )

      result2 = Evilution::Result::MutationResult.new(
        mutation: mutation2,
        status: :survived,
        duration: 0.2
      )

      test_command_builder = ->(_mutation) { ->(_m) { { passed: true } } }

      allow(isolator).to receive(:call)
        .and_return(mutation_result, result2)

      results = worker.call(mutations: [mutation, mutation2], test_command_builder: test_command_builder, timeout: 10)

      expect(results.size).to eq(2)
      expect(results.first).to eq(mutation_result)
      expect(results.last).to eq(result2)
    end
  end
end
