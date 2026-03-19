# frozen_string_literal: true

require "evilution/runner"

RSpec.describe Evilution::Runner do
  let(:config) do
    Evilution::Config.new(
      target_files: ["lib/example.rb"],
      format: :json,
      timeout: 5,
      quiet: true,
      baseline: false,
      isolation: :fork,
      skip_config_file: true
    )
  end

  let(:subject_obj) { double("Subject", name: "Example#foo", file_path: "lib/example.rb", line_number: 3, release_node!: nil) }

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
      diff: "- a >= b\n+ a > b",
      strip_sources!: nil
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

    it "strips source strings from mutations after execution" do
      expect(mutation).to receive(:strip_sources!)

      runner.call
    end

    it "releases AST nodes from subjects after mutation generation" do
      expect(subject_obj).to receive(:release_node!)

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
          diff: "- x\n+ nil",
          strip_sources!: nil
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
             source: "def foo\n  x + 1\nend",
             release_node!: nil)
    end

    let(:subject_outside_range) do
      double("Subject",
             name: "Example#bar",
             file_path: "lib/example.rb",
             line_number: 50,
             source: "def bar\n  y\nend",
             release_node!: nil)
    end

    let(:subject_other_file) do
      double("Subject",
             name: "Other#baz",
             file_path: "lib/other.rb",
             line_number: 1,
             source: "def baz\n  z\nend",
             release_node!: nil)
    end

    let(:config) do
      Evilution::Config.new(
        target_files: ["lib/example.rb", "lib/other.rb"],
        line_ranges: { "lib/example.rb" => 15..30 },
        format: :json,
        timeout: 5,
        quiet: true,
        baseline: false,
        isolation: :fork,
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
             line_number: 3,
             release_node!: nil)
    end

    let(:non_matching_subject) do
      double("Subject",
             name: "Example#bar",
             file_path: "lib/example.rb",
             line_number: 10,
             release_node!: nil)
    end

    let(:config) do
      Evilution::Config.new(
        target_files: ["lib/example.rb"],
        target: "Example#foo",
        format: :json,
        timeout: 5,
        quiet: true,
        baseline: false,
        isolation: :fork,
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
        baseline: false,
        isolation: :fork,
        skip_config_file: true
      )
      no_match_runner = described_class.new(config: no_match_config)

      expect { no_match_runner.call }.to raise_error(Evilution::Error, /no method found matching 'Example#nonexistent'/)
    end
  end

  describe "#call with class-level target filtering" do
    let(:foo_subject) do
      double("Subject",
             name: "Example#foo",
             file_path: "lib/example.rb",
             line_number: 3,
             release_node!: nil)
    end

    let(:bar_subject) do
      double("Subject",
             name: "Example#bar",
             file_path: "lib/example.rb",
             line_number: 10,
             release_node!: nil)
    end

    let(:other_subject) do
      double("Subject",
             name: "Other#baz",
             file_path: "lib/example.rb",
             line_number: 20,
             release_node!: nil)
    end

    before do
      parser = instance_double(Evilution::AST::Parser)
      allow(Evilution::AST::Parser).to receive(:new).and_return(parser)
      allow(parser).to receive(:call).with("lib/example.rb").and_return([foo_subject, bar_subject, other_subject])

      registry = instance_double(Evilution::Mutator::Registry)
      allow(Evilution::Mutator::Registry).to receive(:default).and_return(registry)
      allow(registry).to receive(:mutations_for).and_return([mutation])

      isolator = instance_double(Evilution::Isolation::Fork)
      allow(Evilution::Isolation::Fork).to receive(:new).and_return(isolator)
      allow(isolator).to receive(:call).and_return(mutation_result)
    end

    it "includes all methods in the targeted class" do
      config = Evilution::Config.new(
        target_files: ["lib/example.rb"],
        target: "Example",
        format: :json,
        timeout: 5,
        quiet: true,
        baseline: false,
        isolation: :fork,
        skip_config_file: true
      )
      runner = described_class.new(config: config)
      registry = Evilution::Mutator::Registry.default

      expect(registry).to receive(:mutations_for).with(foo_subject).and_return([mutation])
      expect(registry).to receive(:mutations_for).with(bar_subject).and_return([mutation])
      expect(registry).not_to receive(:mutations_for).with(other_subject)

      runner.call
    end

    it "matches namespaced classes" do
      namespaced_subject = double("Subject",
                                  name: "Foo::Bar#method1",
                                  file_path: "lib/example.rb",
                                  line_number: 5,
                                  release_node!: nil)

      parser = Evilution::AST::Parser.new
      allow(parser).to receive(:call).with("lib/example.rb").and_return([namespaced_subject, other_subject])

      config = Evilution::Config.new(
        target_files: ["lib/example.rb"],
        target: "Foo::Bar",
        format: :json,
        timeout: 5,
        quiet: true,
        baseline: false,
        isolation: :fork,
        skip_config_file: true
      )
      runner = described_class.new(config: config)
      registry = Evilution::Mutator::Registry.default

      expect(registry).to receive(:mutations_for).with(namespaced_subject).and_return([mutation])
      expect(registry).not_to receive(:mutations_for).with(other_subject)

      runner.call
    end

    it "raises an error when no subjects match the class target" do
      config = Evilution::Config.new(
        target_files: ["lib/example.rb"],
        target: "Nonexistent",
        format: :json,
        timeout: 5,
        quiet: true,
        baseline: false,
        isolation: :fork,
        skip_config_file: true
      )
      runner = described_class.new(config: config)

      expect { runner.call }.to raise_error(Evilution::Error, /no method found matching 'Nonexistent'/)
    end
  end

  describe "#call with diff filtering" do
    let(:config) do
      Evilution::Config.new(
        target_files: ["lib/example.rb"],
        format: :json,
        timeout: 5,
        quiet: true,
        baseline: false,
        diff_base: "HEAD~1",
        isolation: :fork,
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
        baseline: false,
        isolation: :fork,
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
        baseline: false,
        isolation: :fork,
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
        diff: "- x\n+ nil",
        strip_sources!: nil
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
        diff: "- true\n+ false",
        strip_sources!: nil
      )
    end

    let(:config) do
      Evilution::Config.new(
        target_files: ["lib/example.rb"],
        fail_fast: 1,
        format: :json,
        timeout: 5,
        quiet: true,
        baseline: false,
        isolation: :fork,
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

    it "marks as truncated even when threshold reached on last mutation" do
      one_mutation_config = Evilution::Config.new(
        target_files: ["lib/example.rb"],
        fail_fast: 1,
        format: :json,
        timeout: 5,
        quiet: true,
        baseline: false,
        isolation: :fork,
        skip_config_file: true
      )
      one_mutation_runner = described_class.new(config: one_mutation_config)

      registry = Evilution::Mutator::Registry.default
      allow(registry).to receive(:mutations_for).and_return([mutation])

      isolator = Evilution::Isolation::Fork.new
      allow(isolator).to receive(:call).and_return(survived_result)

      result = one_mutation_runner.call

      expect(result.total).to eq(1)
      expect(result).to be_truncated
    end

    it "does not truncate when survivors are below threshold" do
      fail_fast_config = Evilution::Config.new(
        target_files: ["lib/example.rb"],
        fail_fast: 5,
        baseline: false,
        format: :json,
        timeout: 5,
        quiet: true,
        isolation: :fork,
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
        baseline: false,
        isolation: :fork,
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
        baseline: false,
        isolation: :fork,
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
        baseline: false,
        isolation: :fork,
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
        baseline: false,
        isolation: :fork,
        skip_config_file: true
      )
      no_files_runner = described_class.new(config: no_files_config)

      expect { no_files_runner.call }.to raise_error(Evilution::Error, /no changed Ruby files/)
    end
  end

  describe "#call with baseline detection" do
    let(:config) do
      Evilution::Config.new(
        target_files: ["lib/example.rb"],
        format: :json,
        timeout: 5,
        quiet: true,
        isolation: :fork,
        skip_config_file: true
      )
    end

    let(:survived_result) do
      Evilution::Result::MutationResult.new(
        mutation: mutation,
        status: :survived,
        duration: 0.1
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
      allow(isolator).to receive(:call).and_return(survived_result)
    end

    it "reclassifies survived mutations as neutral when baseline spec fails" do
      baseline_result = Evilution::Baseline::Result.new(
        failed_spec_files: Set["spec/example_spec.rb"],
        duration: 0.5
      )
      baseline = instance_double(Evilution::Baseline)
      allow(Evilution::Baseline).to receive(:new).and_return(baseline)
      allow(baseline).to receive(:call).and_return(baseline_result)

      spec_resolver = instance_double(Evilution::SpecResolver)
      allow(Evilution::SpecResolver).to receive(:new).and_return(spec_resolver)
      allow(spec_resolver).to receive(:call).with("lib/example.rb").and_return("spec/example_spec.rb")

      result = runner.call

      expect(result.results.first.status).to eq(:neutral)
      expect(result.survived).to eq(0)
      expect(result.neutral).to eq(1)
    end

    it "keeps survived mutations when baseline spec passes" do
      baseline_result = Evilution::Baseline::Result.new(
        failed_spec_files: Set.new,
        duration: 0.5
      )
      baseline = instance_double(Evilution::Baseline)
      allow(Evilution::Baseline).to receive(:new).and_return(baseline)
      allow(baseline).to receive(:call).and_return(baseline_result)

      result = runner.call

      expect(result.results.first.status).to eq(:survived)
      expect(result.survived).to eq(1)
      expect(result.neutral).to eq(0)
    end

    it "does not reclassify killed mutations" do
      killed = Evilution::Result::MutationResult.new(
        mutation: mutation, status: :killed, duration: 0.1
      )
      isolator = Evilution::Isolation::Fork.new
      allow(isolator).to receive(:call).and_return(killed)

      baseline_result = Evilution::Baseline::Result.new(
        failed_spec_files: Set["spec/example_spec.rb"],
        duration: 0.5
      )
      baseline = instance_double(Evilution::Baseline)
      allow(Evilution::Baseline).to receive(:new).and_return(baseline)
      allow(baseline).to receive(:call).and_return(baseline_result)

      spec_resolver = instance_double(Evilution::SpecResolver)
      allow(Evilution::SpecResolver).to receive(:new).and_return(spec_resolver)
      allow(spec_resolver).to receive(:call).with("lib/example.rb").and_return("spec/example_spec.rb")

      result = runner.call

      expect(result.results.first.status).to eq(:killed)
    end

    it "does not count neutral mutations toward fail_fast" do
      mutation2 = double(
        "Mutation2",
        subject: subject_obj,
        operator_name: "nil_replacement",
        original_source: "x",
        mutated_source: "nil",
        file_path: "lib/example.rb",
        line: 5,
        column: 0,
        diff: "- x\n+ nil",
        strip_sources!: nil
      )
      survived2 = Evilution::Result::MutationResult.new(
        mutation: mutation2, status: :survived, duration: 0.1
      )

      registry = Evilution::Mutator::Registry.default
      allow(registry).to receive(:mutations_for).and_return([mutation, mutation2])

      isolator = Evilution::Isolation::Fork.new
      allow(isolator).to receive(:call).and_return(survived_result, survived2)

      baseline_result = Evilution::Baseline::Result.new(
        failed_spec_files: Set["spec/example_spec.rb"],
        duration: 0.5
      )
      baseline = instance_double(Evilution::Baseline)
      allow(Evilution::Baseline).to receive(:new).and_return(baseline)
      allow(baseline).to receive(:call).and_return(baseline_result)

      spec_resolver = instance_double(Evilution::SpecResolver)
      allow(Evilution::SpecResolver).to receive(:new).and_return(spec_resolver)
      allow(spec_resolver).to receive(:call).with("lib/example.rb").and_return("spec/example_spec.rb")

      ff_config = Evilution::Config.new(
        target_files: ["lib/example.rb"],
        fail_fast: 1,
        format: :json,
        timeout: 5,
        quiet: true,
        isolation: :fork,
        skip_config_file: true
      )
      ff_runner = described_class.new(config: ff_config)

      result = ff_runner.call

      expect(result.total).to eq(2)
      expect(result).not_to be_truncated
    end

    context "with --no-baseline" do
      let(:no_baseline_config) do
        Evilution::Config.new(
          target_files: ["lib/example.rb"],
          format: :json,
          timeout: 5,
          quiet: true,
          baseline: false,
          isolation: :fork,
          skip_config_file: true
        )
      end

      it "skips baseline when disabled" do
        no_baseline_runner = described_class.new(config: no_baseline_config)

        expect(Evilution::Baseline).not_to receive(:new)

        result = no_baseline_runner.call

        expect(result.results.first.status).to eq(:survived)
      end
    end
  end

  describe "progress indicator" do
    let(:text_config) do
      Evilution::Config.new(
        target_files: ["lib/example.rb"],
        format: :text,
        timeout: 5,
        quiet: false,
        baseline: false,
        isolation: :fork,
        skip_config_file: true
      )
    end

    let(:quiet_config) do
      Evilution::Config.new(
        target_files: ["lib/example.rb"],
        format: :text,
        timeout: 5,
        quiet: true,
        baseline: false,
        isolation: :fork,
        skip_config_file: true
      )
    end

    let(:json_config) do
      Evilution::Config.new(
        target_files: ["lib/example.rb"],
        format: :json,
        timeout: 5,
        quiet: false,
        baseline: false,
        isolation: :fork,
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

    def capture_stderr_with_tty(tty: true)
      io = StringIO.new
      allow(io).to receive(:tty?).and_return(tty)
      original = $stderr
      $stderr = io
      yield
      io.string
    ensure
      $stderr = original
    end

    it "prints progress to stderr in text mode when TTY" do
      text_runner = described_class.new(config: text_config)
      output = capture_stderr_with_tty { text_runner.call }
      expect(output).to match(/mutation 1 killed/)
    end

    it "does not print progress in quiet mode" do
      quiet_runner = described_class.new(config: quiet_config)
      output = capture_stderr_with_tty { quiet_runner.call }
      expect(output).not_to include("mutation")
    end

    it "does not print progress in json mode" do
      json_runner = described_class.new(config: json_config)
      output = capture_stderr_with_tty { json_runner.call }
      expect(output).not_to include("mutation")
    end

    it "does not print progress when stderr is not a TTY" do
      text_runner = described_class.new(config: text_config)
      output = capture_stderr_with_tty(tty: false) { text_runner.call }
      expect(output).not_to include("mutation")
    end

    it "includes the mutation status in progress output" do
      survived_result = Evilution::Result::MutationResult.new(
        mutation: mutation, status: :survived, duration: 0.1
      )
      isolator = Evilution::Isolation::Fork.new
      allow(isolator).to receive(:call).and_return(survived_result)

      text_runner = described_class.new(config: text_config)
      output = capture_stderr_with_tty { text_runner.call }
      expect(output).to match(/mutation 1 survived/)
    end
  end

  describe "parallel execution" do
    let(:mutation2) do
      double(
        "Mutation2",
        subject: subject_obj,
        operator_name: "boolean_literal_replacement",
        original_source: "true",
        mutated_source: "false",
        file_path: "lib/example.rb",
        line: 5,
        column: 4,
        diff: "- true\n+ false",
        strip_sources!: nil
      )
    end

    let(:mutation_result2) do
      Evilution::Result::MutationResult.new(
        mutation: mutation2,
        status: :survived,
        duration: 0.2
      )
    end

    let(:parallel_config) do
      Evilution::Config.new(
        target_files: ["lib/example.rb"],
        format: :json,
        timeout: 5,
        quiet: true,
        jobs: 2,
        baseline: false,
        isolation: :fork,
        skip_config_file: true
      )
    end

    before do
      parser = instance_double(Evilution::AST::Parser)
      allow(Evilution::AST::Parser).to receive(:new).and_return(parser)
      allow(parser).to receive(:call).with("lib/example.rb").and_return([subject_obj])

      registry = instance_double(Evilution::Mutator::Registry)
      allow(Evilution::Mutator::Registry).to receive(:default).and_return(registry)
      allow(registry).to receive(:mutations_for).with(subject_obj).and_return([mutation, mutation2])

      isolator = instance_double(Evilution::Isolation::Fork)
      allow(Evilution::Isolation::Fork).to receive(:new).and_return(isolator)
      allow(isolator).to receive(:call).and_return(mutation_result, mutation_result2)
    end

    it "returns all results when using parallel execution" do
      pool = instance_double(Evilution::Parallel::Pool)
      allow(Evilution::Parallel::Pool).to receive(:new).with(size: 2).and_return(pool)
      compact = [
        { status: :killed, duration: 0.1, child_rss_kb: nil, memory_delta_kb: nil },
        { status: :survived, duration: 0.2, child_rss_kb: nil, memory_delta_kb: nil }
      ]
      allow(pool).to receive(:map).and_return(compact)

      parallel_runner = described_class.new(config: parallel_config)
      result = parallel_runner.call

      expect(result.total).to eq(2)
    end

    it "uses sequential execution when jobs is 1" do
      sequential_config = Evilution::Config.new(
        target_files: ["lib/example.rb"],
        format: :json,
        timeout: 5,
        quiet: true,
        jobs: 1,
        baseline: false,
        isolation: :fork,
        skip_config_file: true
      )
      sequential_runner = described_class.new(config: sequential_config)

      expect(Evilution::Parallel::Pool).not_to receive(:new)

      sequential_runner.call
    end

    it "uses Parallel::Pool when jobs > 1" do
      pool = instance_double(Evilution::Parallel::Pool)
      allow(Evilution::Parallel::Pool).to receive(:new).with(size: 2).and_return(pool)
      compact = [
        { status: :killed, duration: 0.1, child_rss_kb: nil, memory_delta_kb: nil },
        { status: :survived, duration: 0.2, child_rss_kb: nil, memory_delta_kb: nil }
      ]
      allow(pool).to receive(:map).and_return(compact)

      parallel_runner = described_class.new(config: parallel_config)
      parallel_runner.call

      expect(Evilution::Parallel::Pool).to have_received(:new).with(size: 2)
    end

    it "strips source strings from mutations in parallel path" do
      pool = instance_double(Evilution::Parallel::Pool)
      allow(Evilution::Parallel::Pool).to receive(:new).with(size: 2).and_return(pool)
      compact = [
        { status: :killed, duration: 0.1, child_rss_kb: nil, memory_delta_kb: nil },
        { status: :survived, duration: 0.2, child_rss_kb: nil, memory_delta_kb: nil }
      ]
      allow(pool).to receive(:map).and_return(compact)

      expect(mutation).to receive(:strip_sources!)
      expect(mutation2).to receive(:strip_sources!)

      parallel_runner = described_class.new(config: parallel_config)
      parallel_runner.call
    end

    it "sends compact hashes through the pool instead of full MutationResults" do
      pool = instance_double(Evilution::Parallel::Pool)
      allow(Evilution::Parallel::Pool).to receive(:new).with(size: 2).and_return(pool)

      captured_block = nil
      allow(pool).to receive(:map) do |batch, &block|
        captured_block = block
        batch.map { |item| block.call(item) }
      end

      worker_isolator = instance_double(Evilution::Isolation::InProcess)
      allow(Evilution::Isolation::InProcess).to receive(:new).and_return(worker_isolator)
      allow(worker_isolator).to receive(:call).and_return(mutation_result, mutation_result2)

      parallel_runner = described_class.new(config: parallel_config)
      parallel_runner.call

      # Verify block returns a hash, not a MutationResult
      allow(worker_isolator).to receive(:call).and_return(mutation_result)
      result = captured_block.call(mutation)
      expect(result).to be_a(Hash)
      expect(result).to have_key(:status)
      expect(result).not_to have_key(:mutation)
    end

    it "respects fail_fast and truncates early" do
      mutation3 = double(
        "Mutation3",
        subject: subject_obj,
        operator_name: "nil_replacement",
        original_source: "nil",
        mutated_source: "0",
        file_path: "lib/example.rb",
        line: 7,
        column: 4,
        diff: "- nil\n+ 0",
        strip_sources!: nil
      )

      registry = Evilution::Mutator::Registry.default
      allow(registry).to receive(:mutations_for).with(subject_obj).and_return([mutation, mutation2, mutation3])

      ff_config = Evilution::Config.new(
        target_files: ["lib/example.rb"],
        format: :json,
        timeout: 5,
        quiet: true,
        jobs: 1,
        fail_fast: 1,
        baseline: false,
        isolation: :fork,
        skip_config_file: true
      )

      survived = Evilution::Result::MutationResult.new(
        mutation: mutation, status: :survived, duration: 0.1
      )
      isolator = Evilution::Isolation::Fork.new
      allow(isolator).to receive(:call).and_return(survived)

      ff_runner = described_class.new(config: ff_config)
      result = ff_runner.call

      expect(result.truncated?).to be true
      expect(result.total).to be < 3
    end
  end

  describe "isolation selection" do
    before do
      parser = instance_double(Evilution::AST::Parser)
      allow(Evilution::AST::Parser).to receive(:new).and_return(parser)
      allow(parser).to receive(:call).with("lib/example.rb").and_return([subject_obj])

      registry = instance_double(Evilution::Mutator::Registry)
      allow(Evilution::Mutator::Registry).to receive(:default).and_return(registry)
      allow(registry).to receive(:mutations_for).with(subject_obj).and_return([mutation])
    end

    it "uses InProcess when isolation is :auto and jobs=1" do
      auto_config = Evilution::Config.new(
        target_files: ["lib/example.rb"], jobs: 1, quiet: true,
        baseline: false, skip_config_file: true
      )

      isolator = instance_double(Evilution::Isolation::InProcess)
      allow(Evilution::Isolation::InProcess).to receive(:new).and_return(isolator)
      allow(isolator).to receive(:call).and_return(mutation_result)

      described_class.new(config: auto_config).call

      expect(Evilution::Isolation::InProcess).to have_received(:new)
    end

    it "uses InProcess inside pool workers when isolation is :auto and jobs>1" do
      auto_config = Evilution::Config.new(
        target_files: ["lib/example.rb"], jobs: 2, quiet: true,
        baseline: false, skip_config_file: true
      )

      in_process_isolator = instance_double(Evilution::Isolation::InProcess)
      allow(Evilution::Isolation::InProcess).to receive(:new).and_return(in_process_isolator)
      allow(in_process_isolator).to receive(:call).and_return(mutation_result)
      allow(Evilution::Isolation::Fork).to receive(:new)

      pool = instance_double(Evilution::Parallel::Pool)
      allow(Evilution::Parallel::Pool).to receive(:new).and_return(pool)
      allow(pool).to receive(:map) do |batch, &block|
        batch.map { |item| block.call(item) }
      end

      described_class.new(config: auto_config).call

      expect(in_process_isolator).to have_received(:call)
      expect(Evilution::Isolation::Fork).not_to have_received(:new)
    end

    it "uses InProcess inside pool workers even when isolation is :fork" do
      fork_config = Evilution::Config.new(
        target_files: ["lib/example.rb"], isolation: :fork, jobs: 2, quiet: true,
        baseline: false, skip_config_file: true
      )

      fork_isolator = instance_double(Evilution::Isolation::Fork)
      allow(Evilution::Isolation::Fork).to receive(:new).and_return(fork_isolator)
      allow(fork_isolator).to receive(:call)

      in_process_isolator = instance_double(Evilution::Isolation::InProcess)
      allow(Evilution::Isolation::InProcess).to receive(:new).and_return(in_process_isolator)
      allow(in_process_isolator).to receive(:call).and_return(mutation_result)

      pool = instance_double(Evilution::Parallel::Pool)
      allow(Evilution::Parallel::Pool).to receive(:new).and_return(pool)
      allow(pool).to receive(:map) do |batch, &block|
        batch.map { |item| block.call(item) }
      end

      described_class.new(config: fork_config).call

      expect(in_process_isolator).to have_received(:call)
      expect(fork_isolator).not_to have_received(:call)
    end

    it "uses Fork when isolation is :fork and jobs=1" do
      fork_config = Evilution::Config.new(
        target_files: ["lib/example.rb"], isolation: :fork, quiet: true,
        baseline: false, skip_config_file: true
      )

      isolator = instance_double(Evilution::Isolation::Fork)
      allow(Evilution::Isolation::Fork).to receive(:new).and_return(isolator)
      allow(isolator).to receive(:call).and_return(mutation_result)

      described_class.new(config: fork_config).call

      expect(Evilution::Isolation::Fork).to have_received(:new)
    end

    it "uses InProcess when isolation is :in_process" do
      ip_config = Evilution::Config.new(
        target_files: ["lib/example.rb"], isolation: :in_process, quiet: true,
        baseline: false, skip_config_file: true
      )

      isolator = instance_double(Evilution::Isolation::InProcess)
      allow(Evilution::Isolation::InProcess).to receive(:new).and_return(isolator)
      allow(isolator).to receive(:call).and_return(mutation_result)

      described_class.new(config: ip_config).call

      expect(Evilution::Isolation::InProcess).to have_received(:new)
    end
  end

  describe "lazy mutation generation" do
    let(:lazy_config) do
      Evilution::Config.new(
        target_files: ["lib/example.rb"],
        format: :json, timeout: 5, quiet: true,
        baseline: false, isolation: :fork,
        skip_config_file: true
      )
    end

    let(:subject_a) { double("SubjectA", name: "A#foo", file_path: "lib/example.rb", line_number: 1, release_node!: nil) }
    let(:subject_b) { double("SubjectB", name: "B#bar", file_path: "lib/example.rb", line_number: 10, release_node!: nil) }

    let(:mutation_a) do
      double("MutationA",
             subject: subject_a, operator_name: "op_a",
             original_source: "a", mutated_source: "b",
             file_path: "lib/example.rb", line: 1, column: 0,
             diff: "- a\n+ b", strip_sources!: nil)
    end

    let(:mutation_b) do
      double("MutationB",
             subject: subject_b, operator_name: "op_b",
             original_source: "c", mutated_source: "d",
             file_path: "lib/example.rb", line: 10, column: 0,
             diff: "- c\n+ d", strip_sources!: nil)
    end

    before do
      parser = instance_double(Evilution::AST::Parser)
      allow(Evilution::AST::Parser).to receive(:new).and_return(parser)
      allow(parser).to receive(:call).with("lib/example.rb").and_return([subject_a, subject_b])
    end

    it "generates mutations lazily per-subject during execution" do
      generation_order = []

      registry = instance_double(Evilution::Mutator::Registry)
      allow(Evilution::Mutator::Registry).to receive(:default).and_return(registry)
      allow(registry).to receive(:mutations_for) do |subject|
        generation_order << subject.name
        subject == subject_a ? [mutation_a] : [mutation_b]
      end

      execution_order = []
      isolator = instance_double(Evilution::Isolation::Fork)
      allow(Evilution::Isolation::Fork).to receive(:new).and_return(isolator)
      allow(isolator).to receive(:call) do |mutation:, **|
        execution_order << mutation.subject.name
        Evilution::Result::MutationResult.new(
          mutation: mutation, status: :killed, duration: 0.1
        )
      end

      result = described_class.new(config: lazy_config).call

      expect(result.total).to eq(2)
      # Subject A's mutations are generated and executed before subject B's are generated
      expect(generation_order).to eq(%w[A#foo B#bar])
      expect(execution_order).to eq(%w[A#foo B#bar])
    end

    it "runs baseline before generating any mutations" do
      call_sequence = []

      registry = instance_double(Evilution::Mutator::Registry)
      allow(Evilution::Mutator::Registry).to receive(:default).and_return(registry)
      allow(registry).to receive(:mutations_for) do |_subject|
        call_sequence << :mutations_for
        [mutation_a]
      end

      isolator = instance_double(Evilution::Isolation::Fork)
      allow(Evilution::Isolation::Fork).to receive(:new).and_return(isolator)
      allow(isolator).to receive(:call).and_return(
        Evilution::Result::MutationResult.new(mutation: mutation_a, status: :killed, duration: 0.1)
      )

      baseline_config = Evilution::Config.new(
        target_files: ["lib/example.rb"],
        format: :json, timeout: 5, quiet: true,
        isolation: :fork, skip_config_file: true
      )

      baseline = instance_double(Evilution::Baseline)
      allow(Evilution::Baseline).to receive(:new).and_return(baseline)
      allow(baseline).to receive(:call) do |_subjects|
        call_sequence << :baseline
        Evilution::Baseline::Result.new(failed_spec_files: Set.new, duration: 0.1)
      end

      described_class.new(config: baseline_config).call

      # Baseline runs before any mutations_for calls
      baseline_index = call_sequence.index(:baseline)
      first_mutation_index = call_sequence.index(:mutations_for)
      expect(baseline_index).to be < first_mutation_index
    end
  end
end
