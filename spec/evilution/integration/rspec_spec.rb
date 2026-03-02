# frozen_string_literal: true

require "tempfile"
require "evilution/integration/rspec"

RSpec.describe Evilution::Integration::RSpec do
  let(:source_file) { Tempfile.new(["mutation_target", ".rb"]) }

  let(:original_source) { "class Calculator\n  def add(a, b)\n    a + b\n  end\nend\n" }
  let(:mutated_source) { "class Calculator\n  def add(a, b)\n    a - b\n  end\nend\n" }

  let(:mutation) do
    double(
      "Mutation",
      file_path: source_file.path,
      original_source: original_source,
      mutated_source: mutated_source
    )
  end

  before do
    source_file.write(original_source)
    source_file.flush
    allow(RSpec).to receive(:reset)
  end

  after do
    source_file.close!
  end

  subject(:integration) { described_class.new(test_files: ["spec/some_spec.rb"]) }

  describe "#call" do
    it "writes the mutated source to disk before running" do
      allow(RSpec::Core::Runner).to receive(:run).and_return(1)

      integration.call(mutation)

      # File should be restored after call
      expect(File.read(source_file.path)).to eq(original_source)
    end

    it "returns passed: false when rspec exits non-zero" do
      allow(RSpec::Core::Runner).to receive(:run).and_return(1)

      result = integration.call(mutation)

      expect(result[:passed]).to be false
    end

    it "returns passed: true when rspec exits zero" do
      allow(RSpec::Core::Runner).to receive(:run).and_return(0)

      result = integration.call(mutation)

      expect(result[:passed]).to be true
    end

    it "restores the original file even when runner raises" do
      allow(RSpec::Core::Runner).to receive(:run).and_raise("boom")

      integration.call(mutation)

      expect(File.read(source_file.path)).to eq(original_source)
    end

    it "returns error info when runner raises" do
      allow(RSpec::Core::Runner).to receive(:run).and_raise("boom")

      result = integration.call(mutation)

      expect(result[:passed]).to be false
      expect(result[:error]).to eq("boom")
    end

    it "passes test files to the runner" do
      expect(RSpec::Core::Runner).to receive(:run) do |args, _out, _err|
        expect(args).to include("spec/some_spec.rb")
        0
      end

      integration.call(mutation)
    end

    it "resets RSpec between runs" do
      allow(RSpec::Core::Runner).to receive(:run).and_return(0)

      integration.call(mutation)

      expect(RSpec).to have_received(:reset)
    end

    it "defaults to spec/ directory when no test files given and no convention match" do
      integration_default = described_class.new
      allow(Dir).to receive(:exist?).with("spec").and_return(true)
      allow(File).to receive(:exist?).and_return(false)

      expect(RSpec::Core::Runner).to receive(:run) do |args, _out, _err|
        expect(args).to include("spec")
        0
      end

      integration_default.call(mutation)
    end
  end

  describe "convention-based test file detection" do
    let(:lib_mutation) do
      double(
        "Mutation",
        file_path: "lib/calculator.rb",
        original_source: original_source,
        mutated_source: mutated_source
      )
    end

    subject(:integration_auto) { described_class.new }

    it "maps lib/foo.rb to spec/foo_spec.rb when the file exists" do
      allow(File).to receive(:read).with("lib/calculator.rb").and_return(original_source)
      allow(File).to receive(:write)
      allow(File).to receive(:exist?).and_return(false)
      allow(File).to receive(:exist?).with("spec/calculator_spec.rb").and_return(true)

      expect(RSpec::Core::Runner).to receive(:run) do |args, _out, _err|
        expect(args).to include("spec/calculator_spec.rb")
        0
      end

      integration_auto.call(lib_mutation)
    end

    it "maps lib/foo/bar.rb to spec/foo/bar_spec.rb" do
      nested_mutation = double(
        "Mutation",
        file_path: "lib/foo/bar.rb",
        original_source: original_source,
        mutated_source: mutated_source
      )
      allow(File).to receive(:read).with("lib/foo/bar.rb").and_return(original_source)
      allow(File).to receive(:write)
      allow(File).to receive(:exist?).and_return(false)
      allow(File).to receive(:exist?).with("spec/foo/bar_spec.rb").and_return(true)

      expect(RSpec::Core::Runner).to receive(:run) do |args, _out, _err|
        expect(args).to include("spec/foo/bar_spec.rb")
        0
      end

      integration_auto.call(nested_mutation)
    end
  end
end
