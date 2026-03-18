# frozen_string_literal: true

require "evilution/runner"

RSpec.describe Evilution::Runner, "memory instrumentation" do
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

  before do
    allow(Evilution::Memory).to receive(:rss_mb).and_return(42.5)

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
    stderr_io = StringIO.new
    stdout_io = StringIO.new
    allow(stderr_io).to receive(:tty?).and_return(tty)
    original_stderr = $stderr
    original_stdout = $stdout
    $stderr = stderr_io
    $stdout = stdout_io
    yield
    stderr_io.string
  ensure
    $stderr = original_stderr
    $stdout = original_stdout
  end

  context "with verbose enabled" do
    let(:config) do
      Evilution::Config.new(
        target_files: ["lib/example.rb"],
        format: :text,
        timeout: 5,
        verbose: true,
        quiet: false,
        baseline: false,
        isolation: :fork,
        skip_config_file: true
      )
    end

    let(:runner) { described_class.new(config: config) }

    it "logs memory after parsing subjects" do
      output = capture_stderr_with_tty { runner.call }
      expect(output).to match(/\[memory\] after parse_subjects: 42\.5 MB/)
    end

    it "logs memory after generating mutations" do
      output = capture_stderr_with_tty { runner.call }
      expect(output).to match(/\[memory\] after generate_mutations: 42\.5 MB/)
    end

    it "logs memory after mutation run completes" do
      output = capture_stderr_with_tty { runner.call }
      expect(output).to match(/\[memory\] after run_mutations: 42\.5 MB/)
    end

    it "includes mutation count context" do
      output = capture_stderr_with_tty { runner.call }
      expect(output).to match(/1 subjects/)
      expect(output).to match(/1 mutations/)
    end

    it "logs per-mutation child_rss_kb when available" do
      result_with_rss = Evilution::Result::MutationResult.new(
        mutation: mutation, status: :killed, duration: 0.1, child_rss_kb: 51_200
      )
      isolator = Evilution::Isolation::Fork.new
      allow(isolator).to receive(:call).and_return(result_with_rss)

      output = capture_stderr_with_tty { runner.call }
      expect(output).to match(/\[verbose\].*child_rss: 50\.0 MB/)
    end

    it "logs per-mutation memory_delta_kb when available" do
      result_with_delta = Evilution::Result::MutationResult.new(
        mutation: mutation, status: :killed, duration: 0.1, memory_delta_kb: 2400
      )
      isolator = Evilution::Isolation::Fork.new
      allow(isolator).to receive(:call).and_return(result_with_delta)

      output = capture_stderr_with_tty { runner.call }
      expect(output).to match(/\[verbose\].*delta: \+2\.3 MB/)
    end

    it "logs GC heap_live_slots in per-mutation output" do
      output = capture_stderr_with_tty { runner.call }
      expect(output).to match(/\[verbose\].*heap_live_slots: \d+/)
    end

    it "does not log per-mutation diagnostics when no memory data" do
      output = capture_stderr_with_tty { runner.call }
      expect(output).not_to match(/\[verbose\].*child_rss:/)
      expect(output).not_to match(/\[verbose\].*delta:/)
    end
  end

  context "with verbose disabled" do
    let(:config) do
      Evilution::Config.new(
        target_files: ["lib/example.rb"],
        format: :text,
        timeout: 5,
        verbose: false,
        quiet: false,
        baseline: false,
        isolation: :fork,
        skip_config_file: true
      )
    end

    let(:runner) { described_class.new(config: config) }

    it "does not log memory snapshots" do
      output = capture_stderr_with_tty { runner.call }
      expect(output).not_to include("[memory]")
    end
  end

  context "with quiet enabled" do
    let(:config) do
      Evilution::Config.new(
        target_files: ["lib/example.rb"],
        format: :text,
        timeout: 5,
        verbose: true,
        quiet: true,
        baseline: false,
        isolation: :fork,
        skip_config_file: true
      )
    end

    let(:runner) { described_class.new(config: config) }

    it "does not log memory snapshots when quiet overrides verbose" do
      output = capture_stderr_with_tty { runner.call }
      expect(output).not_to include("[memory]")
    end
  end

  context "parallel mode with verbose" do
    let(:config) do
      Evilution::Config.new(
        target_files: ["lib/example.rb"],
        format: :text,
        timeout: 5,
        verbose: true,
        quiet: false,
        jobs: 2,
        baseline: false,
        isolation: :fork,
        skip_config_file: true
      )
    end

    let(:runner) { described_class.new(config: config) }

    it "logs memory after each batch" do
      pool = instance_double(Evilution::Parallel::Pool)
      allow(Evilution::Parallel::Pool).to receive(:new).with(size: 2).and_return(pool)
      allow(pool).to receive(:map).and_return([mutation_result])

      output = capture_stderr_with_tty { runner.call }
      expect(output).to match(/\[memory\] after batch: 42\.5 MB/)
    end
  end
end
