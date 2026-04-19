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

  def stub_minitest_run(passed: true)
    allow(Minitest).to receive(:__run) do |reporter, _options|
      reporter.record(Minitest::Result.new("test_stub")) if passed
    end
  end

  def stub_minitest_run_failed
    allow(Minitest).to receive(:__run) do |reporter, _options|
      result = Minitest::Result.new("test_stub")
      result.failures << Minitest::Assertion.new("expected true")
      reporter.record(result)
    end
  end

  describe "#call" do
    before do
      stub_minitest_run_failed
      allow(integration).to receive(:load)
    end

    it "returns passed: false when tests fail" do
      result = integration.call(mutation)

      expect(result[:passed]).to be false
    end

    it "returns passed: true when tests pass" do
      stub_minitest_run(passed: true)

      result = integration.call(mutation)

      expect(result[:passed]).to be true
    end

    it "returns error result when run raises" do
      allow(Minitest).to receive(:__run).and_raise("boom")

      result = integration.call(mutation)

      expect(result[:passed]).to be false
      expect(result[:error]).to eq("boom")
    end

    it "returns error info when minitest raises" do
      allow(Minitest).to receive(:__run).and_raise("boom")

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
      stub_minitest_run(passed: true)

      allow(Minitest).to receive(:__run).and_wrap_original do |method, *args|
        expect(test_file_loaded).to be true
        method.call(*args)
      end

      integration.call(mutation)
    end

    it "includes test_command in the result" do
      stub_minitest_run(passed: true)

      result = integration.call(mutation)

      expect(result[:test_command]).to include("test/some_test.rb")
    end

    it "clears minitest runnables before each run" do
      stub_minitest_run(passed: true)
      allow(Minitest).to receive(:__run).and_wrap_original do |method, *args|
        expect(Minitest::Runnable.runnables).to be_empty
        method.call(*args)
      end

      # Simulate a pre-existing runnable
      stub_class = Class.new(Minitest::Test)
      expect(Minitest::Runnable.runnables).to include(stub_class)

      integration.call(mutation)
    ensure
      Minitest::Runnable.runnables.delete(stub_class)
    end
  end

  describe "setup_integration hooks" do
    before do
      stub_minitest_run(passed: true)
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
      stub_minitest_run(passed: true)
    end

    it "uses provided test_files" do
      custom = described_class.new(test_files: ["test/foo_test.rb", "test/bar_test.rb"])
      allow(custom).to receive(:load)

      expect(custom).to receive(:load).with(File.expand_path("test/foo_test.rb"))
      expect(custom).to receive(:load).with(File.expand_path("test/bar_test.rb"))

      custom.call(mutation)
    end

    it "returns an unresolved result when no matching test is found (fail-fast default)" do
      default = described_class.new
      allow(default).to receive(:load)

      result = default.call(mutation)

      expect(result[:unresolved]).to be true
      expect(result[:passed]).to be false
      expect(result[:error]).to match(/no.*test/i)
    end

    it "falls back to globbed test files when fallback_to_full_suite is true" do
      default = described_class.new(fallback_to_full_suite: true)
      allow(default).to receive(:load)

      result = default.call(mutation)

      expect(result[:unresolved]).to be_falsey
      expect(result[:test_command]).to include("test")
    end

    it "uses injected spec_selector when provided" do
      injected = instance_double(Evilution::SpecSelector)
      allow(injected).to receive(:call).with(mutation.file_path).and_return(["test/injected_test.rb"])
      custom = described_class.new(spec_selector: injected)
      allow(custom).to receive(:load)

      expect(custom).to receive(:load).with(File.expand_path("test/injected_test.rb"))

      custom.call(mutation)
    end

    it "returns unresolved when injected spec_selector returns nil" do
      injected = instance_double(Evilution::SpecSelector)
      allow(injected).to receive(:call).with(mutation.file_path).and_return(nil)
      custom = described_class.new(spec_selector: injected)

      result = custom.call(mutation)

      expect(result[:unresolved]).to be true
    end
  end

  describe "crash detection" do
    before do
      allow(integration).to receive(:load)
    end

    it "flags test_crashed with error detail when all failures are crashes" do
      allow(Minitest).to receive(:__run) do |reporter, _options|
        result = Minitest::Result.new("test_crash")
        result.failures << Minitest::UnexpectedError.new(NoMethodError.new("undefined"))
        reporter.record(result)
      end

      result = integration.call(mutation)

      expect(result[:passed]).to be false
      expect(result[:test_crashed]).to be true
      expect(result[:error]).to include("test crashes")
      expect(result[:error]).to include("NoMethodError")
    end

    it "returns killed (no error) when failures include assertions" do
      stub_minitest_run_failed

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

  describe ".baseline_runner" do
    it "returns a callable" do
      expect(described_class.baseline_runner).to respond_to(:call)
    end
  end

  describe ".baseline_options" do
    it "includes a runner" do
      options = described_class.baseline_options
      expect(options[:runner]).to respond_to(:call)
    end

    it "includes minitest-configured spec_resolver" do
      options = described_class.baseline_options
      expect(options[:spec_resolver]).to be_a(Evilution::SpecResolver)
    end

    it "sets fallback_dir to test" do
      options = described_class.baseline_options
      expect(options[:fallback_dir]).to eq("test")
    end
  end
end
