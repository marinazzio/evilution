# frozen_string_literal: true

require "evilution/runner"

RSpec.describe Evilution::Runner do
  let(:config) do
    Evilution::Config.new(
      target_files: ["lib/example.rb"],
      format: :json,
      timeout: 5,
      quiet: true,
      jobs: 1,
      coverage: false,
      skip_config_file: true
    )
  end

  let(:subject_obj) { double("Subject", name: "Example#foo", file_path: "lib/example.rb", line_number: 3) }

  let(:mutation) do
    double(
      "Mutation",
      subject: subject_obj,
      operator_name: "comparison_replacement",
      original_source: "a >= b",
      mutated_source: "a > b",
      file_path: "lib/example.rb",
      line: 3,
      column: 4,
      diff: "- a >= b\n+ a > b"
    )
  end

  let(:mutation_result) do
    Evilution::Result::MutationResult.new(
      mutation: mutation,
      status: :killed,
      duration: 0.1
    )
  end

  subject(:runner) { described_class.new(config: config) }

  describe "#call" do
    before do
      parser = instance_double(Evilution::AST::Parser)
      allow(Evilution::AST::Parser).to receive(:new).and_return(parser)
      allow(parser).to receive(:call).with("lib/example.rb").and_return([subject_obj])

      registry = instance_double(Evilution::Mutator::Registry)
      allow(Evilution::Mutator::Registry).to receive(:default).and_return(registry)
      allow(registry).to receive(:mutations_for).with(subject_obj).and_return([mutation])

      isolator = instance_double(Evilution::Isolation::Fork)
      allow(Evilution::Isolation::Fork).to receive(:new).and_return(isolator)
      allow(isolator).to receive(:call).and_return(mutation_result)
    end

    it "returns a Summary" do
      result = runner.call

      expect(result).to be_a(Evilution::Result::Summary)
    end

    it "includes all mutation results" do
      result = runner.call

      expect(result.total).to eq(1)
      expect(result.killed).to eq(1)
    end

    it "records total duration" do
      result = runner.call

      expect(result.duration).to be > 0
    end

    it "parses target files from config" do
      parser = Evilution::AST::Parser.new
      expect(parser).to receive(:call).with("lib/example.rb").and_return([subject_obj])

      runner.call
    end

    it "generates mutations for each subject" do
      registry = Evilution::Mutator::Registry.default
      expect(registry).to receive(:mutations_for).with(subject_obj).and_return([mutation])

      runner.call
    end

    it "runs each mutation through the isolator" do
      isolator = Evilution::Isolation::Fork.new
      expect(isolator).to receive(:call).with(
        mutation: mutation,
        test_command: anything,
        timeout: 5
      ).and_return(mutation_result)

      runner.call
    end
  end

  describe "#call with parallel execution" do
    let(:config) do
      Evilution::Config.new(
        target_files: ["lib/example.rb"],
        format: :json,
        timeout: 5,
        quiet: true,
        jobs: 4,
        coverage: false,
        skip_config_file: true
      )
    end

    let(:mutation2) do
      double(
        "Mutation",
        subject: subject_obj,
        operator_name: "nil_replacement",
        original_source: "x",
        mutated_source: "nil",
        file_path: "lib/example.rb",
        line: 5,
        column: 0,
        diff: "- x\n+ nil"
      )
    end

    before do
      parser = instance_double(Evilution::AST::Parser)
      allow(Evilution::AST::Parser).to receive(:new).and_return(parser)
      allow(parser).to receive(:call).with("lib/example.rb").and_return([subject_obj])

      registry = instance_double(Evilution::Mutator::Registry)
      allow(Evilution::Mutator::Registry).to receive(:default).and_return(registry)
      allow(registry).to receive(:mutations_for).with(subject_obj).and_return([mutation, mutation2])

      pool = instance_double(Evilution::Parallel::Pool)
      allow(Evilution::Parallel::Pool).to receive(:new).with(jobs: 4).and_return(pool)
      allow(pool).to receive(:call).and_return([mutation_result, mutation_result])
    end

    it "uses Parallel::Pool when jobs > 1 and multiple mutations exist" do
      pool = Evilution::Parallel::Pool.new(jobs: 4)
      expect(pool).to receive(:call).with(
        mutations: [mutation, mutation2],
        test_command_builder: anything,
        timeout: 5
      ).and_return([mutation_result, mutation_result])

      runner.call
    end
  end

  describe "#call with diff filtering" do
    let(:config) do
      Evilution::Config.new(
        target_files: ["lib/example.rb"],
        format: :json,
        timeout: 5,
        quiet: true,
        jobs: 1,
        diff_base: "HEAD~1",
        coverage: false,
        skip_config_file: true
      )
    end

    before do
      parser = instance_double(Evilution::AST::Parser)
      allow(Evilution::AST::Parser).to receive(:new).and_return(parser)
      allow(parser).to receive(:call).with("lib/example.rb").and_return([subject_obj])

      diff_parser = instance_double(Evilution::Diff::Parser)
      allow(Evilution::Diff::Parser).to receive(:new).and_return(diff_parser)
      allow(diff_parser).to receive(:parse).with("HEAD~1").and_return([{ file: "lib/example.rb", lines: [1..10] }])

      file_filter = instance_double(Evilution::Diff::FileFilter)
      allow(Evilution::Diff::FileFilter).to receive(:new).and_return(file_filter)
      allow(file_filter).to receive(:filter).and_return([subject_obj])

      registry = instance_double(Evilution::Mutator::Registry)
      allow(Evilution::Mutator::Registry).to receive(:default).and_return(registry)
      allow(registry).to receive(:mutations_for).with(subject_obj).and_return([mutation])

      isolator = instance_double(Evilution::Isolation::Fork)
      allow(Evilution::Isolation::Fork).to receive(:new).and_return(isolator)
      allow(isolator).to receive(:call).and_return(mutation_result)
    end

    it "filters subjects through diff when diff_base is set" do
      diff_parser = Evilution::Diff::Parser.new
      expect(diff_parser).to receive(:parse).with("HEAD~1").and_return([{ file: "lib/example.rb", lines: [1..10] }])

      runner.call
    end

    it "applies file filter to subjects" do
      file_filter = Evilution::Diff::FileFilter.new
      expect(file_filter).to receive(:filter).and_return([subject_obj])

      runner.call
    end
  end

  describe "#call with no mutations" do
    before do
      parser = instance_double(Evilution::AST::Parser)
      allow(Evilution::AST::Parser).to receive(:new).and_return(parser)
      allow(parser).to receive(:call).and_return([])

      registry = instance_double(Evilution::Mutator::Registry)
      allow(Evilution::Mutator::Registry).to receive(:default).and_return(registry)
    end

    it "returns an empty summary" do
      result = runner.call

      expect(result.total).to eq(0)
      expect(result.score).to eq(0.0)
    end
  end

  describe "#call with unknown integration" do
    let(:config) do
      Evilution::Config.new(
        target_files: ["lib/example.rb"],
        integration: :minitest,
        quiet: true,
        jobs: 1,
        coverage: false,
        skip_config_file: true
      )
    end

    before do
      parser = instance_double(Evilution::AST::Parser)
      allow(Evilution::AST::Parser).to receive(:new).and_return(parser)
      allow(parser).to receive(:call).and_return([subject_obj])

      registry = instance_double(Evilution::Mutator::Registry)
      allow(Evilution::Mutator::Registry).to receive(:default).and_return(registry)
      allow(registry).to receive(:mutations_for).and_return([mutation])

      isolator = instance_double(Evilution::Isolation::Fork)
      allow(Evilution::Isolation::Fork).to receive(:new).and_return(isolator)
    end

    it "raises an error" do
      expect { runner.call }.to raise_error(Evilution::Error, /unknown integration/)
    end
  end

  describe "#call with coverage enabled" do
    let(:config) do
      Evilution::Config.new(
        target_files: ["lib/example.rb"],
        format: :json,
        timeout: 5,
        quiet: true,
        jobs: 1,
        coverage: true,
        skip_config_file: true
      )
    end

    let(:covered_mutation) do
      double(
        "Mutation",
        subject: subject_obj,
        operator_name: "comparison_replacement",
        original_source: "a >= b",
        mutated_source: "a > b",
        file_path: "lib/example.rb",
        line: 3,
        column: 4,
        diff: "- a >= b\n+ a > b"
      )
    end

    let(:uncovered_mutation) do
      double(
        "Mutation",
        subject: subject_obj,
        operator_name: "nil_replacement",
        original_source: "x",
        mutated_source: "nil",
        file_path: "lib/example.rb",
        line: 10,
        column: 0,
        diff: "- x\n+ nil"
      )
    end

    let(:expanded_path) { File.expand_path("lib/example.rb") }

    let(:coverage_data) do
      { expanded_path => [nil, 1, 1, 1, nil, nil, nil, nil, nil, nil] }
    end

    let(:collector) { instance_double(Evilution::Coverage::Collector) }
    let(:test_map) { Evilution::Coverage::TestMap.new(coverage_data) }

    before do
      parser = instance_double(Evilution::AST::Parser)
      allow(Evilution::AST::Parser).to receive(:new).and_return(parser)
      allow(parser).to receive(:call).with("lib/example.rb").and_return([subject_obj])

      registry = instance_double(Evilution::Mutator::Registry)
      allow(Evilution::Mutator::Registry).to receive(:default).and_return(registry)
      allow(registry).to receive(:mutations_for).with(subject_obj).and_return([covered_mutation, uncovered_mutation])

      allow(Evilution::Coverage::Collector).to receive(:new).and_return(collector)
      allow(collector).to receive(:call).and_return(coverage_data)

      allow(Dir).to receive(:glob).with("spec/**/*_spec.rb").and_return(["spec/example_spec.rb"])

      isolator = instance_double(Evilution::Isolation::Fork)
      allow(Evilution::Isolation::Fork).to receive(:new).and_return(isolator)
      allow(isolator).to receive(:call).and_return(
        Evilution::Result::MutationResult.new(mutation: covered_mutation, status: :killed, duration: 0.1)
      )
    end

    it "calls Coverage::Collector with discovered spec files" do
      expect(collector).to receive(:call).with(test_files: ["spec/example_spec.rb"])

      runner.call
    end

    it "skips uncovered mutations without running them through isolator" do
      isolator = Evilution::Isolation::Fork.new
      expect(isolator).to receive(:call).once

      result = runner.call

      expect(result.total).to eq(2)
    end

    it "marks uncovered mutations as survived" do
      result = runner.call

      survived = result.results.select(&:survived?)
      expect(survived.size).to eq(1)
      expect(survived.first.mutation).to eq(uncovered_mutation)
      expect(survived.first.duration).to eq(0.0)
    end

    it "runs covered mutations through isolator normally" do
      isolator = Evilution::Isolation::Fork.new
      expect(isolator).to receive(:call).with(
        mutation: covered_mutation,
        test_command: anything,
        timeout: 5
      ).and_return(
        Evilution::Result::MutationResult.new(mutation: covered_mutation, status: :killed, duration: 0.1)
      )

      result = runner.call

      killed = result.results.select(&:killed?)
      expect(killed.size).to eq(1)
      expect(killed.first.mutation).to eq(covered_mutation)
    end
  end

  describe "#call with coverage disabled" do
    it "does not call Coverage::Collector" do
      parser = instance_double(Evilution::AST::Parser)
      allow(Evilution::AST::Parser).to receive(:new).and_return(parser)
      allow(parser).to receive(:call).and_return([subject_obj])

      registry = instance_double(Evilution::Mutator::Registry)
      allow(Evilution::Mutator::Registry).to receive(:default).and_return(registry)
      allow(registry).to receive(:mutations_for).and_return([mutation])

      isolator = instance_double(Evilution::Isolation::Fork)
      allow(Evilution::Isolation::Fork).to receive(:new).and_return(isolator)
      allow(isolator).to receive(:call).and_return(mutation_result)

      expect(Evilution::Coverage::Collector).not_to receive(:new)

      runner.call
    end
  end
end
