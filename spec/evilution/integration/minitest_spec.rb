# frozen_string_literal: true

require "tempfile"
require "minitest"
require "evilution/integration/minitest"

RSpec.describe Evilution::Integration::Minitest do
  let(:source_file) { Tempfile.new(["mutation_target", ".rb"]) }

  let(:original_source) { "class Calculator\n  def add(a, b)\n    a + b\n  end\nend\n" }
  let(:mutated_source) { "class Calculator\n  def add(a, b)\n    a - b\n  end\nend\n" }

  let(:mutation) do
    double(
      "Mutation",
      file_path: source_file.path,
      original_source: original_source,
      mutated_source: mutated_source,
      diff: nil
    )
  end

  before do
    source_file.write(original_source)
    source_file.flush
  end

  after do
    source_file.close!
  end

  subject(:integration) { described_class.new(test_files: ["test/some_test.rb"]) }

  describe "#call" do
    before do
      allow(Minitest).to receive(:run).and_return(false)
      allow(integration).to receive(:load)
    end

    it "returns passed: false when minitest returns false" do
      result = integration.call(mutation)

      expect(result[:passed]).to be false
    end

    it "returns passed: true when minitest returns true" do
      allow(Minitest).to receive(:run).and_return(true)

      result = integration.call(mutation)

      expect(result[:passed]).to be true
    end

    it "restores the original file even when minitest raises" do
      allow(Minitest).to receive(:run).and_raise("boom")

      integration.call(mutation)

      expect(File.read(source_file.path)).to eq(original_source)
    end

    it "returns error info when minitest raises" do
      allow(Minitest).to receive(:run).and_raise("boom")

      result = integration.call(mutation)

      expect(result[:passed]).to be false
      expect(result[:error]).to eq("boom")
    end

    it "loads test files before running" do
      test_file_loaded = false
      allow(integration).to receive(:load).and_call_original
      allow(integration).to receive(:load).with(File.expand_path("test/some_test.rb")) do
        test_file_loaded = true
      end
      allow(Minitest).to receive(:run) do
        expect(test_file_loaded).to be true
        true
      end

      integration.call(mutation)
    end

    it "includes test_command in the result" do
      allow(Minitest).to receive(:run).and_return(true)

      result = integration.call(mutation)

      expect(result[:test_command]).to include("test/some_test.rb")
    end

    it "clears minitest runnables before each run" do
      allow(Minitest).to receive(:run) do
        expect(Minitest::Runnable.runnables).to be_empty
        true
      end

      # Simulate a pre-existing runnable
      stub_class = Class.new(Minitest::Test)
      expect(Minitest::Runnable.runnables).to include(stub_class)

      integration.call(mutation)
    ensure
      Minitest::Runnable.runnables.delete(stub_class)
    end

    it "captures stdout during minitest run" do
      allow(integration).to receive(:load)
      allow(Minitest).to receive(:run) do
        $stdout.print "minitest output"
        true
      end

      expect { integration.call(mutation) }.not_to output.to_stdout
    end
  end

  describe "setup_integration hooks" do
    before do
      allow(Minitest).to receive(:run).and_return(true)
      allow(integration).to receive(:load)
    end

    it "fires setup_integration hooks with :minitest" do
      hooks = Evilution::Hooks::Registry.new
      received = nil
      hooks.register(:setup_integration_pre) { |payload| received = payload }
      hooked = described_class.new(test_files: ["test/some_test.rb"], hooks: hooks)
      allow(hooked).to receive(:load)

      hooked.call(mutation)

      expect(received[:integration]).to eq(:minitest)
    end

    it "only fires setup hooks on first call" do
      hooks = Evilution::Hooks::Registry.new
      count = 0
      hooks.register(:setup_integration_pre) { count += 1 }
      hooked = described_class.new(test_files: ["test/some_test.rb"], hooks: hooks)
      allow(hooked).to receive(:load)

      hooked.call(mutation)
      hooked.call(mutation)

      expect(count).to eq(1)
    end
  end

  describe "test file selection" do
    before do
      allow(Minitest).to receive(:run).and_return(true)
    end

    it "uses provided test_files" do
      custom = described_class.new(test_files: ["test/foo_test.rb", "test/bar_test.rb"])
      allow(custom).to receive(:load)

      expect(custom).to receive(:load).with(File.expand_path("test/foo_test.rb"))
      expect(custom).to receive(:load).with(File.expand_path("test/bar_test.rb"))

      custom.call(mutation)
    end

    it "falls back to test/ when no test_files provided and resolver finds nothing" do
      default = described_class.new
      allow(default).to receive(:load)

      result = default.call(mutation)

      expect(result[:test_command]).to include("test")
    end
  end

  describe "crash detection" do
    before do
      allow(integration).to receive(:load)
    end

    it "returns error when all failures are crashes" do
      detector = instance_double(
        Evilution::Integration::MinitestCrashDetector,
        only_crashes?: true,
        crash_summary: "NoMethodError (1 crash)"
      )
      allow(detector).to receive(:reset)
      allow(Evilution::Integration::MinitestCrashDetector).to receive(:new).and_return(detector)
      allow(Minitest).to receive(:run).and_return(false)

      result = integration.call(mutation)

      expect(result[:passed]).to be false
      expect(result[:error]).to include("test crashes")
      expect(result[:error]).to include("NoMethodError")
    end

    it "returns killed (no error) when failures include assertions" do
      detector = instance_double(
        Evilution::Integration::MinitestCrashDetector,
        only_crashes?: false
      )
      allow(detector).to receive(:reset)
      allow(Evilution::Integration::MinitestCrashDetector).to receive(:new).and_return(detector)
      allow(Minitest).to receive(:run).and_return(false)

      result = integration.call(mutation)

      expect(result[:passed]).to be false
      expect(result).not_to have_key(:error)
    end
  end

  describe "raises when minitest not available" do
    it "raises Evilution::Error on LoadError" do
      fresh = described_class.new(test_files: ["test/some_test.rb"])
      fresh.instance_variable_set(:@minitest_loaded, false)
      allow(fresh).to receive(:require).with("minitest").and_raise(LoadError, "cannot load such file -- minitest")

      expect { fresh.call(mutation) }.to raise_error(Evilution::Error, /minitest is required/)
    end
  end
end
