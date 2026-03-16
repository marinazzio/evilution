# frozen_string_literal: true

require "evilution/runner"

RSpec.describe Evilution::Runner do
  let(:config) do
    Evilution::Config.new(
      target_files: ["lib/example.rb"],
      format: :json,
      timeout: 5,
      quiet: true,
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

    context "with multiple mutations" do
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

      let(:mutation_result2) do
        Evilution::Result::MutationResult.new(
          mutation: mutation2,
          status: :survived,
          duration: 0.2
        )
      end

      before do
        registry = Evilution::Mutator::Registry.default
        allow(registry).to receive(:mutations_for).with(subject_obj).and_return([mutation, mutation2])

        isolator = Evilution::Isolation::Fork.new
        allow(isolator).to receive(:call).and_return(mutation_result, mutation_result2)
      end

      it "runs isolator for each mutation" do
        isolator = Evilution::Isolation::Fork.new
        expect(isolator).to receive(:call).twice.and_return(mutation_result, mutation_result2)

        runner.call
      end

      it "returns results for all mutations" do
        result = runner.call

        expect(result.total).to eq(2)
        expect(result.killed).to eq(1)
        expect(result.survived).to eq(1)
      end
    end
  end

  describe "#call with line-range filtering" do
    let(:subject_in_range) do
      double("Subject",
             name: "Example#foo",
             file_path: "lib/example.rb",
             line_number: 20,
             source: "def foo\n  x + 1\nend")
    end

    let(:subject_outside_range) do
      double("Subject",
             name: "Example#bar",
             file_path: "lib/example.rb",
             line_number: 50,
             source: "def bar\n  y\nend")
    end

    let(:subject_other_file) do
      double("Subject",
             name: "Other#baz",
             file_path: "lib/other.rb",
             line_number: 1,
             source: "def baz\n  z\nend")
    end

    let(:config) do
      Evilution::Config.new(
        target_files: ["lib/example.rb", "lib/other.rb"],
        line_ranges: { "lib/example.rb" => 15..30 },
        format: :json,
        timeout: 5,
        quiet: true,
        skip_config_file: true
      )
    end

    before do
      parser = instance_double(Evilution::AST::Parser)
      allow(Evilution::AST::Parser).to receive(:new).and_return(parser)
      allow(parser).to receive(:call).with("lib/example.rb").and_return([subject_in_range, subject_outside_range])
      allow(parser).to receive(:call).with("lib/other.rb").and_return([subject_other_file])

      registry = instance_double(Evilution::Mutator::Registry)
      allow(Evilution::Mutator::Registry).to receive(:default).and_return(registry)
      allow(registry).to receive(:mutations_for).and_return([mutation])

      isolator = instance_double(Evilution::Isolation::Fork)
      allow(Evilution::Isolation::Fork).to receive(:new).and_return(isolator)
      allow(isolator).to receive(:call).and_return(mutation_result)
    end

    it "includes subjects overlapping with the line range" do
      registry = Evilution::Mutator::Registry.default
      expect(registry).to receive(:mutations_for).with(subject_in_range).and_return([mutation])

      runner.call
    end

    it "excludes subjects outside the line range" do
      registry = Evilution::Mutator::Registry.default
      expect(registry).not_to receive(:mutations_for).with(subject_outside_range)

      runner.call
    end

    it "includes all subjects from files without a line range constraint" do
      registry = Evilution::Mutator::Registry.default
      expect(registry).to receive(:mutations_for).with(subject_other_file).and_return([mutation])

      runner.call
    end
  end

  describe "#call with target filtering" do
    let(:matching_subject) do
      double("Subject",
             name: "Example#foo",
             file_path: "lib/example.rb",
             line_number: 3)
    end

    let(:non_matching_subject) do
      double("Subject",
             name: "Example#bar",
             file_path: "lib/example.rb",
             line_number: 10)
    end

    let(:config) do
      Evilution::Config.new(
        target_files: ["lib/example.rb"],
        target: "Example#foo",
        format: :json,
        timeout: 5,
        quiet: true,
        skip_config_file: true
      )
    end

    before do
      parser = instance_double(Evilution::AST::Parser)
      allow(Evilution::AST::Parser).to receive(:new).and_return(parser)
      allow(parser).to receive(:call).with("lib/example.rb").and_return([matching_subject, non_matching_subject])

      registry = instance_double(Evilution::Mutator::Registry)
      allow(Evilution::Mutator::Registry).to receive(:default).and_return(registry)
      allow(registry).to receive(:mutations_for).and_return([mutation])

      isolator = instance_double(Evilution::Isolation::Fork)
      allow(Evilution::Isolation::Fork).to receive(:new).and_return(isolator)
      allow(isolator).to receive(:call).and_return(mutation_result)
    end

    it "includes subjects matching the target" do
      registry = Evilution::Mutator::Registry.default
      expect(registry).to receive(:mutations_for).with(matching_subject).and_return([mutation])

      runner.call
    end

    it "excludes subjects not matching the target" do
      registry = Evilution::Mutator::Registry.default
      expect(registry).not_to receive(:mutations_for).with(non_matching_subject)

      runner.call
    end

    it "raises an error when no subjects match the target" do
      no_match_config = Evilution::Config.new(
        target_files: ["lib/example.rb"],
        target: "Example#nonexistent",
        format: :json,
        timeout: 5,
        quiet: true,
        skip_config_file: true
      )
      no_match_runner = described_class.new(config: no_match_config)

      expect { no_match_runner.call }.to raise_error(Evilution::Error, /no method found matching 'Example#nonexistent'/)
    end
  end

  describe "#call with diff filtering" do
    let(:config) do
      Evilution::Config.new(
        target_files: ["lib/example.rb"],
        format: :json,
        timeout: 5,
        quiet: true,
        diff_base: "HEAD~1",
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

  describe "#call with spec_files" do
    let(:config) do
      Evilution::Config.new(
        target_files: ["lib/example.rb"],
        spec_files: ["spec/example_spec.rb"],
        format: :json,
        timeout: 5,
        quiet: true,
        skip_config_file: true
      )
    end

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

    it "passes spec_files to the RSpec integration" do
      expect(Evilution::Integration::RSpec).to receive(:new).with(test_files: ["spec/example_spec.rb"]).and_call_original

      runner.call
    end

    it "passes nil test_files when spec_files is empty" do
      empty_config = Evilution::Config.new(
        target_files: ["lib/example.rb"],
        format: :json,
        timeout: 5,
        quiet: true,
        skip_config_file: true
      )
      empty_runner = described_class.new(config: empty_config)

      expect(Evilution::Integration::RSpec).to receive(:new).with(test_files: nil).and_call_original

      empty_runner.call
    end
  end

  describe "#call with fail_fast" do
    let(:survived_result) do
      Evilution::Result::MutationResult.new(
        mutation: mutation,
        status: :survived,
        duration: 0.1
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

    let(:mutation3) do
      double(
        "Mutation",
        subject: subject_obj,
        operator_name: "boolean_literal_replacement",
        original_source: "true",
        mutated_source: "false",
        file_path: "lib/example.rb",
        line: 7,
        column: 0,
        diff: "- true\n+ false"
      )
    end

    let(:config) do
      Evilution::Config.new(
        target_files: ["lib/example.rb"],
        fail_fast: 1,
        format: :json,
        timeout: 5,
        quiet: true,
        skip_config_file: true
      )
    end

    before do
      parser = instance_double(Evilution::AST::Parser)
      allow(Evilution::AST::Parser).to receive(:new).and_return(parser)
      allow(parser).to receive(:call).with("lib/example.rb").and_return([subject_obj])

      registry = instance_double(Evilution::Mutator::Registry)
      allow(Evilution::Mutator::Registry).to receive(:default).and_return(registry)
      allow(registry).to receive(:mutations_for).and_return([mutation, mutation2, mutation3])

      isolator = instance_double(Evilution::Isolation::Fork)
      allow(Evilution::Isolation::Fork).to receive(:new).and_return(isolator)
      allow(isolator).to receive(:call).and_return(survived_result)
    end

    it "stops after reaching the survivor threshold" do
      isolator = Evilution::Isolation::Fork.new
      expect(isolator).to receive(:call).once.and_return(survived_result)

      result = runner.call

      expect(result.total).to eq(1)
    end

    it "marks the summary as truncated" do
      result = runner.call

      expect(result).to be_truncated
    end

    it "does not mark as truncated when threshold reached on last mutation" do
      one_mutation_config = Evilution::Config.new(
        target_files: ["lib/example.rb"],
        fail_fast: 1,
        format: :json,
        timeout: 5,
        quiet: true,
        skip_config_file: true
      )
      one_mutation_runner = described_class.new(config: one_mutation_config)

      registry = Evilution::Mutator::Registry.default
      allow(registry).to receive(:mutations_for).and_return([mutation])

      isolator = Evilution::Isolation::Fork.new
      allow(isolator).to receive(:call).and_return(survived_result)

      result = one_mutation_runner.call

      expect(result.total).to eq(1)
      expect(result).not_to be_truncated
    end

    it "does not truncate when survivors are below threshold" do
      fail_fast_config = Evilution::Config.new(
        target_files: ["lib/example.rb"],
        fail_fast: 5,
        format: :json,
        timeout: 5,
        quiet: true,
        skip_config_file: true
      )
      fail_fast_runner = described_class.new(config: fail_fast_config)

      isolator = Evilution::Isolation::Fork.new
      allow(isolator).to receive(:call).and_return(survived_result)

      result = fail_fast_runner.call

      expect(result.total).to eq(3)
      expect(result).not_to be_truncated
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

  describe "#call with auto-detected files" do
    let(:config) do
      Evilution::Config.new(
        target_files: [],
        format: :json,
        timeout: 5,
        quiet: true,
        skip_config_file: true
      )
    end

    before do
      changed_files = instance_double(Evilution::Git::ChangedFiles)
      allow(Evilution::Git::ChangedFiles).to receive(:new).and_return(changed_files)
      allow(changed_files).to receive(:call).and_return(["lib/example.rb"])

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

    it "uses git changed files when no target_files provided" do
      result = runner.call

      expect(result.total).to eq(1)
    end

    it "does not use git detection when target_files are provided" do
      explicit_config = Evilution::Config.new(
        target_files: ["lib/example.rb"],
        format: :json,
        timeout: 5,
        quiet: true,
        skip_config_file: true
      )
      explicit_runner = described_class.new(config: explicit_config)

      expect(Evilution::Git::ChangedFiles).not_to receive(:new)

      explicit_runner.call
    end

    it "propagates errors from git changed files detection" do
      changed_files = instance_double(Evilution::Git::ChangedFiles)
      allow(Evilution::Git::ChangedFiles).to receive(:new).and_return(changed_files)
      allow(changed_files).to receive(:call).and_raise(
        Evilution::Error, "no changed Ruby files found since merge base with main"
      )

      no_files_config = Evilution::Config.new(
        target_files: [],
        format: :json,
        timeout: 5,
        quiet: true,
        skip_config_file: true
      )
      no_files_runner = described_class.new(config: no_files_config)

      expect { no_files_runner.call }.to raise_error(Evilution::Error, /no changed Ruby files/)
    end
  end

  describe "progress indicator" do
    let(:text_config) do
      Evilution::Config.new(
        target_files: ["lib/example.rb"],
        format: :text,
        timeout: 5,
        quiet: false,
        skip_config_file: true
      )
    end

    let(:quiet_config) do
      Evilution::Config.new(
        target_files: ["lib/example.rb"],
        format: :text,
        timeout: 5,
        quiet: true,
        skip_config_file: true
      )
    end

    let(:json_config) do
      Evilution::Config.new(
        target_files: ["lib/example.rb"],
        format: :json,
        timeout: 5,
        quiet: false,
        skip_config_file: true
      )
    end

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

    it "prints progress to stderr in text mode" do
      text_runner = described_class.new(config: text_config)
      expect { text_runner.call }.to output(%r{mutation 1/1 killed}).to_stderr
    end

    it "does not print progress in quiet mode" do
      quiet_runner = described_class.new(config: quiet_config)
      expect { quiet_runner.call }.not_to output(/mutation/).to_stderr
    end

    it "does not print progress in json mode" do
      json_runner = described_class.new(config: json_config)
      expect { json_runner.call }.not_to output(/mutation/).to_stderr
    end

    it "includes the mutation status in progress output" do
      survived_result = Evilution::Result::MutationResult.new(
        mutation: mutation, status: :survived, duration: 0.1
      )
      isolator = Evilution::Isolation::Fork.new
      allow(isolator).to receive(:call).and_return(survived_result)

      text_runner = described_class.new(config: text_config)
      expect { text_runner.call }.to output(%r{mutation 1/1 survived}).to_stderr
    end
  end
end
