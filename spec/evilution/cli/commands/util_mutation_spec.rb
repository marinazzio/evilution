# frozen_string_literal: true

require "stringio"
require "tempfile"
require "evilution/cli/commands/util_mutation"
require "evilution/cli/parsed_args"

RSpec.describe Evilution::CLI::Commands::UtilMutation do
  let(:out) { StringIO.new }
  let(:err) { StringIO.new }

  let(:config) { instance_double(Evilution::Config, skip_heredoc_literals?: false) }
  let(:registry) { instance_double("Registry") }
  let(:finder) { instance_double("SubjectFinder", visit: nil, subjects: subjects) }
  let(:prism_result) { instance_double("Prism::ParseResult", failure?: false, value: :ast_root) }
  let(:printer) { instance_double(Evilution::CLI::Printers::UtilMutation, render: nil) }
  let(:subjects) { [:subject_a] }
  let(:mutations) { %i[mutation_a mutation_b] }

  before do
    allow(Evilution::Config).to receive(:new).and_return(config)
    allow(Evilution::Mutator::Registry).to receive(:default).and_return(registry)
    allow(registry).to receive(:mutations_for).and_return(mutations)
    allow(Prism).to receive(:parse).and_return(prism_result)
    allow(Evilution::AST::SubjectFinder).to receive(:new).and_return(finder)
    allow(Evilution::CLI::Printers::UtilMutation).to receive(:new).and_return(printer)
  end

  describe "with --eval source" do
    let(:parsed) do
      Evilution::CLI::ParsedArgs.new(
        command: :util_mutation,
        options: { eval: "def foo; x + y; end", format: :text }
      )
    end
    let(:tmpfile) do
      instance_double(Tempfile, write: nil, flush: nil, path: "/tmp/eval.rb", close!: nil)
    end

    before { allow(Tempfile).to receive(:new).and_return(tmpfile) }

    it "writes the eval code to a tmpfile" do
      described_class.new(parsed, stdout: out, stderr: err).call
      expect(tmpfile).to have_received(:write).with("def foo; x + y; end")
      expect(tmpfile).to have_received(:flush)
    end

    it "invokes the printer with the mutations and format" do
      described_class.new(parsed, stdout: out, stderr: err).call
      expect(Evilution::CLI::Printers::UtilMutation).to have_received(:new).with(mutations, format: :text)
      expect(printer).to have_received(:render).with(out)
    end

    it "returns exit code 0" do
      expect(described_class.new(parsed, stdout: out, stderr: err).call.exit_code).to eq(0)
    end

    it "closes the tmpfile on success" do
      described_class.new(parsed, stdout: out, stderr: err).call
      expect(tmpfile).to have_received(:close!)
    end

    it "closes the tmpfile even when parsing fails" do
      allow(prism_result).to receive(:failure?).and_return(true)
      allow(prism_result).to receive(:errors).and_return([instance_double("ParseError", message: "oops")])

      described_class.new(parsed, stdout: out, stderr: err).call

      expect(tmpfile).to have_received(:close!)
    end
  end

  describe "with a positional file path" do
    let(:path) { "/tmp/example.rb" }
    let(:parsed) do
      Evilution::CLI::ParsedArgs.new(
        command: :util_mutation,
        files: [path],
        options: { format: :text }
      )
    end

    before do
      allow(File).to receive(:exist?).with(path).and_return(true)
      allow(File).to receive(:read).with(path).and_return("def foo; end")
    end

    it "reads the file and renders mutations" do
      result = described_class.new(parsed, stdout: out, stderr: err).call
      expect(File).to have_received(:read).with(path)
      expect(printer).to have_received(:render).with(out)
      expect(result.exit_code).to eq(0)
    end

    it "wraps SystemCallError in Evilution::Error" do
      allow(File).to receive(:read).with(path).and_raise(Errno::EACCES, "denied")
      result = described_class.new(parsed, stdout: out, stderr: err).call
      expect(result.exit_code).to eq(2)
      expect(result.error).to be_a(Evilution::Error)
    end
  end

  describe "with no source" do
    let(:parsed) { Evilution::CLI::ParsedArgs.new(command: :util_mutation, options: {}) }

    it "returns exit code 2 with 'source required' error" do
      result = described_class.new(parsed, stdout: out, stderr: err).call
      expect(result.exit_code).to eq(2)
      expect(result.error).to be_a(Evilution::Error)
      expect(result.error.message).to include("source required")
    end
  end

  describe "with a nonexistent file" do
    let(:parsed) do
      Evilution::CLI::ParsedArgs.new(command: :util_mutation, files: ["/nope.rb"], options: {})
    end

    before { allow(File).to receive(:exist?).with("/nope.rb").and_return(false) }

    it "returns exit code 2 with 'file not found' error" do
      result = described_class.new(parsed, stdout: out, stderr: err).call
      expect(result.exit_code).to eq(2)
      expect(result.error).to be_a(Evilution::Error)
      expect(result.error.message).to include("file not found")
    end
  end

  describe "when no mutations are generated" do
    let(:parsed) do
      Evilution::CLI::ParsedArgs.new(
        command: :util_mutation,
        options: { eval: "def foo; end", format: :text }
      )
    end
    let(:tmpfile) do
      instance_double(Tempfile, write: nil, flush: nil, path: "/tmp/eval.rb", close!: nil)
    end

    before do
      allow(Tempfile).to receive(:new).and_return(tmpfile)
      allow(registry).to receive(:mutations_for).and_return([])
    end

    it "prints 'No mutations generated' and returns 0" do
      result = described_class.new(parsed, stdout: out, stderr: err).call
      expect(out.string).to include("No mutations generated")
      expect(result.exit_code).to eq(0)
      expect(Evilution::CLI::Printers::UtilMutation).not_to have_received(:new)
    end

    it "still closes the tmpfile" do
      described_class.new(parsed, stdout: out, stderr: err).call
      expect(tmpfile).to have_received(:close!)
    end
  end

  describe "when Prism parse fails" do
    let(:parsed) do
      Evilution::CLI::ParsedArgs.new(
        command: :util_mutation,
        options: { eval: "def foo(", format: :text }
      )
    end
    let(:tmpfile) do
      instance_double(Tempfile, write: nil, flush: nil, path: "/tmp/eval.rb", close!: nil)
    end

    before do
      allow(Tempfile).to receive(:new).and_return(tmpfile)
      allow(prism_result).to receive(:failure?).and_return(true)
      allow(prism_result).to receive(:errors)
        .and_return([instance_double("ParseError", message: "syntax error")])
    end

    it "raises Evilution::Error wrapped to exit 2" do
      result = described_class.new(parsed, stdout: out, stderr: err).call
      expect(result.exit_code).to eq(2)
      expect(result.error.message).to include("failed to parse source")
    end
  end

  it "is registered with the dispatcher under :util_mutation" do
    require "evilution/cli/dispatcher"
    expect(Evilution::CLI::Dispatcher.registered?(:util_mutation)).to be(true)
    expect(Evilution::CLI::Dispatcher.lookup(:util_mutation)).to eq(described_class)
  end
end
