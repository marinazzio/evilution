# frozen_string_literal: true

require "stringio"
require "evilution/cli/commands/subjects"
require "evilution/cli/parsed_args"

RSpec.describe Evilution::CLI::Commands::Subjects do
  let(:out) { StringIO.new }
  let(:err) { StringIO.new }
  let(:parsed) { Evilution::CLI::ParsedArgs.new(command: :subjects, files: ["lib/a.rb"]) }

  describe "with no subjects" do
    it "prints 'No subjects found' and returns 0" do
      runner = instance_double(Evilution::Runner, parse_and_filter_subjects: [])
      allow(Evilution::Runner).to receive(:new).and_return(runner)

      result = described_class.new(parsed, stdout: out, stderr: err).call

      expect(result.exit_code).to eq(0)
      expect(out.string).to include("No subjects found")
    end
  end

  describe "with subjects" do
    let(:subject_a) do
      instance_double("Subject", name: "Foo#bar", file_path: "lib/a.rb", line_number: 10, release_node!: nil)
    end
    let(:runner) { instance_double(Evilution::Runner, parse_and_filter_subjects: [subject_a]) }
    let(:registry) { instance_double("Registry") }

    before do
      allow(Evilution::Runner).to receive(:new).and_return(runner)
      allow(Evilution::Mutator::Registry).to receive(:default).and_return(registry)
      allow(registry).to receive(:mutations_for).and_return(%i[m1 m2])
    end

    it "prints entries and returns 0" do
      result = described_class.new(parsed, stdout: out, stderr: err).call
      expect(result.exit_code).to eq(0)
      expect(out.string).to include("Foo#bar")
      expect(out.string).to include("lib/a.rb:10")
      expect(out.string).to include("(2 mutations)")
    end

    it "calls release_node! on each subject" do
      described_class.new(parsed, stdout: out, stderr: err).call
      expect(subject_a).to have_received(:release_node!)
    end
  end

  describe "with stdin error" do
    it "returns an error Result when @stdin_error is set" do
      parsed_with_err = Evilution::CLI::ParsedArgs.new(
        command: :subjects,
        stdin_error: "--stdin cannot be combined with positional file arguments"
      )
      result = described_class.new(parsed_with_err, stdout: out, stderr: err).call
      expect(result.exit_code).to eq(2)
      expect(result.error).to be_a(Evilution::ConfigError)
    end
  end

  it "is registered with the dispatcher under :subjects" do
    require "evilution/cli/dispatcher"
    expect(Evilution::CLI::Dispatcher.registered?(:subjects)).to be(true)
    expect(Evilution::CLI::Dispatcher.lookup(:subjects)).to eq(described_class)
  end
end
