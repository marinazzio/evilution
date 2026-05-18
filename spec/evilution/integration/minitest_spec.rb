# frozen_string_literal: true

require "tempfile"
require "tmpdir"
require "securerandom"
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

  # Anonymous Minitest::Test subclasses created in the dispatch stubs register
  # into Minitest::Runnable.runnables and persist there. run_minitest counts
  # test methods from that registry, so a stubbed dispatch must register a
  # runnable to mimic a real run. Clear the registry after each example.
  after { Minitest::Runnable.runnables.clear }

  # Stub the version-dispatch helper rather than ::Minitest.__run directly so
  # the stubs work whether the installed Minitest is 5.x (has __run) or 6.x
  # (uses run_all_suites). The dispatch method takes the same (reporter, options)
  # signature regardless of underlying Minitest version.
  #
  # Block receives the call args only (no leading instance). RSpec's
  # any_instance binds self to the instance via instance_exec. A real dispatch
  # has at least one registered runnable; register one so run_minitest's
  # registry-based test count is non-zero.
  def stub_minitest_run(passed: true)
    allow_any_instance_of(described_class).to receive(:dispatch_minitest_suites) do |reporter, _options|
      Class.new(Minitest::Test) { define_method(:test_stub) { assert true } }
      reporter.record(Minitest::Result.new("test_stub")) if passed
    end
  end

  def stub_minitest_run_failed
    allow_any_instance_of(described_class).to receive(:dispatch_minitest_suites) do |reporter, _options|
      Class.new(Minitest::Test) { define_method(:test_stub) { assert true } }
      result = Minitest::Result.new("test_stub")
      result.failures << Minitest::Assertion.new("expected true")
      reporter.record(result)
    end
  end

  # Dispatch that registers no runnable — mimics a spec that loads no Minitest
  # suite (wrong --integration, or a non-Minitest framework such as test-unit).
  def stub_minitest_no_tests
    allow_any_instance_of(described_class).to receive(:dispatch_minitest_suites) do |_reporter, _options|
      nil
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
      allow_any_instance_of(described_class).to receive(:dispatch_minitest_suites).and_raise("boom")

      result = integration.call(mutation)

      expect(result[:passed]).to be false
      expect(result[:error]).to eq("boom")
    end

    it "returns error info when minitest raises" do
      allow_any_instance_of(described_class).to receive(:dispatch_minitest_suites).and_raise("boom")

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

      allow_any_instance_of(described_class).to receive(:dispatch_minitest_suites) do |reporter, _options|
        expect(test_file_loaded).to be true
        reporter.record(Minitest::Result.new("test_stub"))
      end

      integration.call(mutation)
    end

    it "includes test_command in the result" do
      stub_minitest_run(passed: true)

      result = integration.call(mutation)

      expect(result[:test_command]).to include("test/some_test.rb")
    end

    it "clears minitest runnables before each run" do
      observed_runnables = nil
      allow_any_instance_of(described_class).to receive(:dispatch_minitest_suites) do |reporter, _options|
        observed_runnables = Minitest::Runnable.runnables.dup
        reporter.record(Minitest::Result.new("test_stub"))
      end

      # Simulate a pre-existing runnable
      stub_class = Class.new(Minitest::Test)
      expect(Minitest::Runnable.runnables).to include(stub_class)

      integration.call(mutation)

      expect(observed_runnables).to be_empty
    ensure
      Minitest::Runnable.runnables.delete(stub_class)
    end
  end

  describe "#call when zero tests run" do
    before do
      stub_minitest_no_tests # dispatch registers no runnable -> 0 test methods
      allow(integration).to receive(:load)
    end

    it "returns an error result instead of reporting the mutation survived" do
      result = integration.call(mutation)

      expect(result[:passed]).to be false
      expect(result[:error]).to match(/0 test methods/)
    end

    it "tags the error so classify_status maps it to :error" do
      result = integration.call(mutation)

      expect(result[:error_class]).to eq("Evilution::Error")
      expect(result).not_to have_key(:test_crashed)
    end

    it "does not classify a zero-test run as passed (survived)" do
      result = integration.call(mutation)

      expect(result[:passed]).not_to be true
    end
  end

  describe "#call when a reporter plugin evicts evilution's reporters" do
    # Minitest::Reporters.use! (and similar plugins) replace the composite's
    # reporters during Minitest.init_plugins. evilution attaches its own
    # SummaryReporter AFTER init so it survives the swap; run_minitest reads
    # the verdict from that reporter and the test count from the runnable
    # registry, both immune to the plugin.

    # Mimics a reporter plugin: during init_plugins (inside
    # initialize_minitest_state), drop the composite's reporters and install
    # the plugin's own.
    def stub_reporter_plugin(plugin_reporter)
      allow(described_class).to receive(:initialize_minitest_state)
        .and_wrap_original do |orig, composite, options|
          orig.call(composite, options)
          composite.reporters.clear
          composite.reporters << plugin_reporter
        end
    end

    def recorded_result(failing:)
      result = Minitest::Result.new("test_real")
      result.failures << Minitest::Assertion.new("boom") if failing
      result
    end

    def stub_dispatch(failing:)
      allow_any_instance_of(described_class).to receive(:dispatch_minitest_suites) do |composite, _options|
        Class.new(Minitest::Test) { define_method(:test_real) { assert true } }
        composite.record(recorded_result(failing: failing))
      end
    end

    before do
      allow(integration).to receive(:load)
      stub_reporter_plugin(Minitest::SummaryReporter.new(StringIO.new, {}))
    end

    it "does not misreport a real run as zero tests" do
      stub_dispatch(failing: false)

      expect(integration.call(mutation)[:error]).to be_nil
    end

    it "preserves a passing outcome" do
      stub_dispatch(failing: false)

      expect(integration.call(mutation)[:passed]).to be true
    end

    it "preserves a failing outcome" do
      stub_dispatch(failing: true)
      result = integration.call(mutation)

      expect(result[:passed]).to be false
      expect(result[:error]).not_to match(/0 test methods/) if result[:error]
    end

    it "still classifies crash-only failures via the crash detector" do
      # The crash detector must survive plugin eviction too: build_minitest_result
      # queries detector.only_crashes? to mark a crash :error rather than :killed.
      allow_any_instance_of(described_class).to receive(:dispatch_minitest_suites) do |composite, _options|
        Class.new(Minitest::Test) { define_method(:test_real) { assert true } }
        result = Minitest::Result.new("test_real")
        result.failures << Minitest::UnexpectedError.new(NoMethodError.new("undefined"))
        composite.record(result)
      end

      result = integration.call(mutation)

      expect(result[:test_crashed]).to be true
      expect(result[:error_class]).to eq("NoMethodError")
    end

    it "does not let a prior mutation's failure poison a later passing mutation" do
      # The plugin reporter is process-global and never reset between runs.
      # Under in_process isolation one process runs every mutation in
      # sequence, so its failures accumulate. run_minitest must read the
      # verdict from evilution's own per-run reporter, not the composite.
      sticky = Minitest::SummaryReporter.new(StringIO.new, {})
      sticky.start
      allow(sticky).to receive(:start) # process-global: never reset between runs
      stub_reporter_plugin(sticky)

      stub_dispatch(failing: true)
      integration.call(mutation)          # mutation 1: genuine failure

      stub_dispatch(failing: false)
      result = integration.call(mutation) # mutation 2: tests pass

      expect(result[:passed]).to be true
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
      allow_any_instance_of(described_class).to receive(:dispatch_minitest_suites) do |reporter, _options|
        Class.new(Minitest::Test) { define_method(:test_crash) { assert true } }
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

  describe "Minitest version compatibility" do
    it "completes the integration pipeline against the installed Minitest without NoMethodError" do
      # End-to-end smoke: invoke the integration with no runnable tests
      # registered. reset_state clears Runnable.runnables before dispatch, so
      # the suite runner sees an empty list and returns cleanly. The point is
      # that the version-dispatch helper resolves to a real Minitest method
      # (run_all_suites on 6.x, __run on 5.x) without raising NoMethodError.
      # Reaching the zero-tests guard proves dispatch itself succeeded — a
      # NoMethodError would have been caught and surfaced as the error instead.
      integration_real = described_class.new(test_files: ["test/some_test.rb"])
      allow(integration_real).to receive(:load)

      result = integration_real.call(mutation)

      expect(result[:error]).to match(/0 test methods/)
      expect(result[:error]).not_to match(/NoMethodError/)
      expect(result[:test_command]).to include("test/some_test.rb")
    end

    it "passes the configured reporter into dispatch_minitest_suites" do
      reporter_observed = nil
      options_observed = nil
      integration_obs = described_class.new(test_files: ["test/some_test.rb"])
      allow(integration_obs).to receive(:load)
      # Replace dispatch entirely (no call-through) so this spec only asserts
      # what evilution hands the suite runner, not what Minitest does next.
      allow(integration_obs).to receive(:dispatch_minitest_suites) do |reporter, options|
        reporter_observed = reporter
        options_observed = options
      end

      integration_obs.call(mutation)

      expect(reporter_observed).to be_a(Minitest::CompositeReporter)
      expect(options_observed).to include(:seed)
    end

    describe ".dispatch_minitest_suites version branching" do
      let(:reporter) { instance_double(Minitest::CompositeReporter) }
      let(:options) { { seed: 0 } }

      it "calls Minitest.run_all_suites when available (Minitest 6.x)" do
        allow(Minitest).to receive(:respond_to?).with(:run_all_suites).and_return(true)
        expect(Minitest).to receive(:run_all_suites).with(reporter, options)

        described_class.dispatch_minitest_suites(reporter, options)
      end

      it "falls back to Minitest.__run when run_all_suites is missing (Minitest 5.x)" do
        allow(Minitest).to receive(:respond_to?).with(:run_all_suites).and_return(false)
        allow(Minitest).to receive(:respond_to?).with(:__run).and_return(true)
        expect(Minitest).to receive(:__run).with(reporter, options)

        described_class.dispatch_minitest_suites(reporter, options)
      end

      it "raises Evilution::Error when neither suite-runner method exists" do
        allow(Minitest).to receive(:respond_to?).with(:run_all_suites).and_return(false)
        allow(Minitest).to receive(:respond_to?).with(:__run).and_return(false)
        stub_const("Minitest::VERSION", "99.0.0")

        expect { described_class.dispatch_minitest_suites(reporter, options) }
          .to raise_error(Evilution::Error, /99\.0\.0.*neither run_all_suites nor __run/)
      end
    end
  end

  describe ".baseline_runner" do
    it "returns a callable" do
      expect(described_class.baseline_runner).to respond_to(:call)
    end
  end

  describe ".stub_autorun!" do
    let(:original_method) { Minitest.singleton_class.instance_method(:autorun) }

    around do |example|
      saved = original_method
      example.run
    ensure
      Minitest.singleton_class.send(:define_method, :autorun, saved)
    end

    it "redefines Minitest.autorun to a no-op owned by the integration file" do
      described_class.stub_autorun!

      location = Minitest.singleton_class.instance_method(:autorun).source_location
      expect(location.first).to end_with("lib/evilution/integration/minitest.rb")
    end

    it "makes Minitest.autorun return nil without raising" do
      described_class.stub_autorun!

      expect(Minitest.autorun).to be_nil
    end

    it "is idempotent" do
      described_class.stub_autorun!
      first_location = Minitest.singleton_class.instance_method(:autorun).source_location

      described_class.stub_autorun!
      second_location = Minitest.singleton_class.instance_method(:autorun).source_location

      expect(second_location).to eq(first_location)
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

  describe ".run_baseline_test_file" do
    # Each fixture defines a uniquely named Minitest::Test subclass. A class is
    # only registered as a runnable on creation (the `inherited` hook); reusing
    # a name across examples would re-open the existing class without
    # re-registering it, so uniqueness keeps registration observable.
    def write_minitest_file(class_name, assertion)
      file = Tempfile.new(["baseline", "_test.rb"])
      file.write(<<~RUBY)
        require "minitest/autorun"
        class #{class_name} < Minitest::Test
          def test_case
            #{assertion}
          end
        end
      RUBY
      file.flush
      file
    end

    let(:unique) { "Baseline#{SecureRandom.hex(6)}Test" }
    let(:passing_file) { write_minitest_file(unique, "assert true") }
    let(:failing_file) { write_minitest_file(unique, 'assert false, "intentional"') }

    after do
      passing_file.close!
      failing_file.close!
    end

    it "returns true when the baseline test file passes" do
      expect(described_class.run_baseline_test_file(passing_file.path)).to be true
    end

    it "returns false when the baseline test file fails" do
      expect(described_class.run_baseline_test_file(failing_file.path)).to be false
    end

    it "loads and runs the test methods from the given file" do
      described_class.run_baseline_test_file(passing_file.path)

      expect(Minitest::Runnable.runnables.map(&:name)).to include(unique)
    end

    it "clears previously registered runnables before loading" do
      stale = Class.new(Minitest::Test)
      expect(Minitest::Runnable.runnables).to include(stale)

      described_class.run_baseline_test_file(passing_file.path)

      expect(Minitest::Runnable.runnables).not_to include(stale)
    end

    it "stubs Minitest.autorun so loading the file installs no autorun handler" do
      Minitest.define_singleton_method(:autorun) { :real_autorun }

      described_class.run_baseline_test_file(passing_file.path)

      location = Minitest.singleton_class.instance_method(:autorun).source_location
      expect(location.first).to end_with("lib/evilution/integration/minitest.rb")
    end
  end

  describe ".baseline_test_files" do
    it "globs *_test.rb files when given a directory" do
      Dir.mktmpdir do |dir|
        File.write(File.join(dir, "foo_test.rb"), "")
        File.write(File.join(dir, "ignored.rb"), "")

        result = described_class.baseline_test_files(dir)

        expect(result).to contain_exactly(File.join(dir, "foo_test.rb"))
      end
    end

    it "wraps a single non-directory file path in an array" do
      Tempfile.create(["single", "_test.rb"]) do |file|
        expect(described_class.baseline_test_files(file.path)).to eq([file.path])
      end
    end

    it "returns an empty list for a directory with no matching test files" do
      Dir.mktmpdir do |dir|
        expect(described_class.baseline_test_files(dir)).to eq([])
      end
    end
  end

  describe ".run_baseline_minitest" do
    after { Minitest::Runnable.runnables.clear }

    it "returns true when all registered runnables pass" do
      Class.new(Minitest::Test) { define_method(:test_ok) { assert true } }

      expect(described_class.run_baseline_minitest).to be true
    end

    it "returns false when a registered runnable fails" do
      Class.new(Minitest::Test) { define_method(:test_bad) { assert false } }

      expect(described_class.run_baseline_minitest).to be false
    end

    it "seeds Minitest before dispatch so a nil seed does not raise a TypeError" do
      # Minitest 5.x's runnable_methods calls srand(Minitest.seed); a nil seed
      # raises TypeError. initialize_minitest_state must seed it first.
      Minitest.seed = nil
      Class.new(Minitest::Test) { define_method(:test_seeded) { assert true } }

      expect { described_class.run_baseline_minitest }.not_to raise_error
    end
  end

  describe ".initialize_minitest_state" do
    let(:reporter) { Minitest::CompositeReporter.new }

    around do |example|
      saved = Minitest.reporter
      example.run
    ensure
      Minitest.reporter = saved
    end

    it "seeds the global RNG so a fixed seed yields a reproducible rand" do
      described_class.initialize_minitest_state(reporter, { seed: 4321 })
      first = rand
      described_class.initialize_minitest_state(reporter, { seed: 4321 })
      second = rand

      expect(second).to eq(first)
    end

    it "uses the provided seed so a different seed yields a different rand" do
      described_class.initialize_minitest_state(reporter, { seed: 4321 })
      first = rand
      described_class.initialize_minitest_state(reporter, { seed: 8765 })
      second = rand

      expect(second).not_to eq(first)
    end

    it "clears Minitest.reporter back to nil after plugin initialization" do
      Minitest.reporter = :stale

      described_class.initialize_minitest_state(reporter, { seed: 0 })

      expect(Minitest.reporter).to be_nil
    end

    it "skips seeding the RNG when the seed is nil rather than calling srand(nil)" do
      # srand(nil) raises TypeError; the guard must short-circuit on a nil seed.
      expect { described_class.initialize_minitest_state(reporter, { seed: nil }) }
        .not_to raise_error
    end

    it "exposes the run's reporter via Minitest.reporter while plugins initialize" do
      # init_plugins runs immediately after the `Minitest.reporter = reporter`
      # assignment; some plugins (pride) read Minitest.reporter during init.
      # Pre-seed a stale sentinel so a dropped/no-op assignment is observable:
      # if line 64 is deleted or its receiver-only form runs, init_plugins
      # would still see the sentinel instead of the run's composite reporter.
      Minitest.reporter = :stale_sentinel
      observed = :not_called
      allow(Minitest).to receive(:init_plugins) do
        observed = Minitest.reporter
      end

      described_class.initialize_minitest_state(reporter, { seed: 0 })

      expect(observed).to equal(reporter)
    end
  end

  describe ".stub_autorun! idempotency" do
    let(:original_autorun) { Minitest.singleton_class.instance_method(:autorun) }

    around do |example|
      saved = original_autorun
      example.run
    ensure
      Minitest.singleton_class.send(:define_method, :autorun, saved)
    end

    it "preserves the already-stubbed method object on a second call" do
      described_class.stub_autorun!
      first = Minitest.singleton_class.instance_method(:autorun)

      described_class.stub_autorun!
      second = Minitest.singleton_class.instance_method(:autorun)

      expect(second).to eq(first)
    end

    it "redefines a non-evilution autorun even when its location matches another file" do
      Minitest.define_singleton_method(:autorun) { :real }
      expect(Minitest.autorun).to eq(:real)

      described_class.stub_autorun!

      expect(Minitest.autorun).to be_nil
    end
  end

  describe "test_command formatting" do
    before { stub_minitest_run(passed: true) }

    it "joins multiple test files with spaces in the command" do
      custom = described_class.new(test_files: ["test/a_test.rb", "test/b_test.rb"])
      allow(custom).to receive(:load)

      result = custom.call(mutation)

      expect(result[:test_command]).to eq("ruby -Itest test/a_test.rb test/b_test.rb")
    end
  end

  describe "unresolved result content" do
    before { stub_minitest_run(passed: true) }

    it "names the mutation's file_path in the unresolved error" do
      default = described_class.new
      allow(default).to receive(:load)

      result = default.call(mutation)

      expect(result[:error]).to include(mutation.file_path)
    end

    it "names the mutation's file_path in the unresolved test_command" do
      default = described_class.new
      allow(default).to receive(:load)

      result = default.call(mutation)

      expect(result[:test_command]).to include(mutation.file_path)
    end
  end

  describe "fallback glob test file selection" do
    before { stub_minitest_run(passed: true) }

    it "falls back to the test directory when the glob finds nothing" do
      default = described_class.new(fallback_to_full_suite: true)
      allow(default).to receive(:load)
      allow(Dir).to receive(:glob).with("test/**/*_test.rb").and_return([])

      result = default.call(mutation)

      expect(result[:test_command]).to eq("ruby -Itest test")
    end

    it "uses the globbed test files when the glob finds matches" do
      default = described_class.new(fallback_to_full_suite: true)
      allow(default).to receive(:load)
      allow(Dir).to receive(:glob)
        .with("test/**/*_test.rb")
        .and_return(["test/found_a_test.rb", "test/found_b_test.rb"])

      result = default.call(mutation)

      expect(result[:test_command]).to eq("ruby -Itest test/found_a_test.rb test/found_b_test.rb")
    end
  end

  describe "warn_unresolved_test behavior" do
    it "warns to stderr when a test cannot be resolved" do
      default = described_class.new
      allow(default).to receive(:load)

      expect { default.call(mutation) }
        .to output(/No matching test found for #{Regexp.escape(mutation.file_path)}/).to_stderr
    end

    it "warns only once per file path across repeated calls" do
      default = described_class.new
      allow(default).to receive(:load)

      output = capture_warn_count { 2.times { default.call(mutation) } }

      expect(output.scan("No matching test found").length).to eq(1)
    end

    def capture_warn_count
      original = $stderr
      $stderr = StringIO.new
      yield
      $stderr.string
    ensure
      $stderr = original
    end
  end

  describe "crash detector reset between mutations" do
    before { allow(integration).to receive(:load) }

    def stub_crash_dispatch
      allow_any_instance_of(described_class).to receive(:dispatch_minitest_suites) do |reporter, _options|
        Class.new(Minitest::Test) { define_method(:test_crash) { assert true } }
        result = Minitest::Result.new("test_crash")
        result.failures << Minitest::UnexpectedError.new(NoMethodError.new("undefined"))
        reporter.record(result)
      end
    end

    it "does not carry crash state from a prior mutation into a passing run" do
      stub_crash_dispatch
      integration.call(mutation) # mutation 1: crash

      stub_minitest_run(passed: true)
      result = integration.call(mutation) # mutation 2: clean pass

      expect(result[:passed]).to be true
      expect(result).not_to have_key(:test_crashed)
    end

    it "resets accumulated assertion failures so a later pure crash is flagged" do
      # Mutation 1 records an assertion failure; mutation 2 records only a
      # crash. Without reset, the stale assertion failure makes only_crashes?
      # false and the crash is mis-classified as :killed instead of :error.
      stub_minitest_run_failed
      integration.call(mutation) # mutation 1: assertion failure

      stub_crash_dispatch
      result = integration.call(mutation) # mutation 2: pure crash

      expect(result[:test_crashed]).to be true
    end
  end

  describe "crash error_class with multiple crash classes" do
    before { allow(integration).to receive(:load) }

    it "omits error_class when crashes span more than one exception class" do
      allow_any_instance_of(described_class).to receive(:dispatch_minitest_suites) do |reporter, _options|
        Class.new(Minitest::Test) { define_method(:test_a) { assert true } }
        first = Minitest::Result.new("test_a")
        first.failures << Minitest::UnexpectedError.new(NoMethodError.new("nme"))
        reporter.record(first)
        second = Minitest::Result.new("test_b")
        second.failures << Minitest::UnexpectedError.new(ArgumentError.new("ae"))
        reporter.record(second)
      end

      result = integration.call(mutation)

      expect(result[:test_crashed]).to be true
      expect(result[:error_class]).to be_nil
    end
  end

  describe "dispatch delegation in the running pipeline" do
    it "actually dispatches registered suites so a failing test is observed as failed" do
      runner = described_class.new(test_files: ["test/some_test.rb"])
      allow(runner).to receive(:load) do
        Class.new(Minitest::Test) { define_method(:test_real_fail) { assert false } }
      end

      result = runner.call(mutation)

      expect(result[:passed]).to be false
    end

    it "actually dispatches registered suites so a passing test is observed as passed" do
      runner = described_class.new(test_files: ["test/some_test.rb"])
      allow(runner).to receive(:load) do
        Class.new(Minitest::Test) { define_method(:test_real_pass) { assert true } }
      end

      result = runner.call(mutation)

      expect(result[:passed]).to be true
    end
  end

  describe "framework loading stubs autorun" do
    let(:original_autorun) { Minitest.singleton_class.instance_method(:autorun) }

    around do |example|
      saved = original_autorun
      example.run
    ensure
      Minitest.singleton_class.send(:define_method, :autorun, saved)
    end

    it "stubs Minitest.autorun when the integration first loads the framework" do
      Minitest.define_singleton_method(:autorun) { :real_autorun }
      stub_minitest_run(passed: true)
      runner = described_class.new(test_files: ["test/some_test.rb"])
      allow(runner).to receive(:load)

      runner.call(mutation)

      location = Minitest.singleton_class.instance_method(:autorun).source_location
      expect(location.first).to end_with("lib/evilution/integration/minitest.rb")
    end
  end

  describe "setup_integration_post hook" do
    before do
      stub_minitest_run(passed: true)
      allow(integration).to receive(:load)
    end

    it "fires the setup_integration_post hook with :minitest" do
      hooks = Evilution::Hooks::Registry.new
      received = nil
      hooks.register(:setup_integration_post) { |payload| received = payload }
      hooked = described_class.new(test_files: ["test/some_test.rb"], hooks: hooks)
      allow(hooked).to receive(:load)

      hooked.call(mutation)

      expect(received).to eq({ integration: :minitest })
    end
  end
end
