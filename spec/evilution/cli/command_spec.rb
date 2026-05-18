# frozen_string_literal: true

require "stringio"
require "evilution/cli/command"
require "evilution/cli/parsed_args"
require "evilution/cli/result"

RSpec.describe Evilution::CLI::Command do
  let(:parsed) { Evilution::CLI::ParsedArgs.new(command: :dummy, options: { foo: 1 }) }
  let(:stdout) { StringIO.new }
  let(:stderr) { StringIO.new }

  let(:happy_subclass) do
    Class.new(described_class) do
      def perform
        0
      end
    end
  end

  let(:error_subclass) do
    Class.new(described_class) do
      def perform
        raise Evilution::Error, "kaboom"
      end
    end
  end

  it "wraps a successful perform in a Result" do
    result = happy_subclass.new(parsed, stdout: stdout, stderr: stderr).call
    expect(result.exit_code).to eq(0)
    expect(result.error).to be_nil
  end

  it "catches Evilution::Error and returns exit code 2 carrying the error" do
    result = error_subclass.new(parsed, stdout: stdout, stderr: stderr).call
    expect(result.exit_code).to eq(2)
    expect(result.error).to be_a(Evilution::Error)
    expect(result.error.message).to eq("kaboom")
  end

  it "raises NotImplementedError when perform is not overridden" do
    expect { described_class.new(parsed).call }.to raise_error(NotImplementedError)
  end

  describe "constructor wiring" do
    let(:full_parsed) do
      Evilution::CLI::ParsedArgs.new(
        command: :dummy,
        options: { foo: 1 },
        files: ["lib/a.rb"],
        line_ranges: { "lib/a.rb" => (1..5) },
        stdin_error: "boom"
      )
    end

    let(:probe_subclass) do
      Class.new(described_class) do
        def ivars
          {
            options: @options,
            files: @files,
            line_ranges: @line_ranges,
            stdin_error: @stdin_error,
            stdout: @stdout,
            stderr: @stderr
          }
        end
      end
    end

    it "assigns options, files, line_ranges and stdin_error from the parsed args" do
      command = probe_subclass.new(full_parsed, stdout: stdout, stderr: stderr)
      expect(command.ivars).to include(
        options: { foo: 1 },
        files: ["lib/a.rb"],
        line_ranges: { "lib/a.rb" => (1..5) },
        stdin_error: "boom"
      )
    end

    it "assigns the provided stdout and stderr streams" do
      command = probe_subclass.new(full_parsed, stdout: stdout, stderr: stderr)
      expect(command.ivars[:stdout]).to be(stdout)
      expect(command.ivars[:stderr]).to be(stderr)
    end
  end

  describe "helper methods" do
    let(:helper_subclass) do
      Class.new(described_class) do
        public :build_operator_options, :build_subject_filter
      end
    end

    let(:command) { helper_subclass.new(parsed, stdout: stdout, stderr: stderr) }

    def config_double(skip_heredoc: false, ignore_patterns: [])
      instance_double(
        Evilution::Config,
        skip_heredoc_literals?: skip_heredoc,
        ignore_patterns: ignore_patterns
      )
    end

    describe "#build_operator_options" do
      it "maps skip_heredoc_literals? from the config" do
        expect(command.build_operator_options(config_double(skip_heredoc: true)))
          .to eq(skip_heredoc_literals: true)
      end

      it "reflects a false skip_heredoc_literals? setting" do
        expect(command.build_operator_options(config_double(skip_heredoc: false)))
          .to eq(skip_heredoc_literals: false)
      end
    end

    describe "#build_subject_filter" do
      it "returns nil when the config has no ignore patterns" do
        expect(command.build_subject_filter(config_double(ignore_patterns: []))).to be_nil
      end

      it "returns a Pattern::Filter instance when ignore patterns are present" do
        require "evilution/ast/pattern/filter"
        filter = command.build_subject_filter(config_double(ignore_patterns: ["call{name=log}"]))
        expect(filter).to be_an_instance_of(Evilution::AST::Pattern::Filter)
      end
    end
  end
end
