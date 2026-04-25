# frozen_string_literal: true

require "tempfile"
require "evilution/integration/rspec"
require "evilution/example_filter"

RSpec.describe Evilution::Integration::RSpec do
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
    allow(RSpec).to receive(:clear_examples)
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

    it "produces independent results across consecutive calls" do
      passing_mutation = double(
        "Mutation",
        file_path: source_file.path,
        original_source: original_source,
        mutated_source: original_source
      )
      failing_mutation = double(
        "Mutation",
        file_path: source_file.path,
        original_source: original_source,
        mutated_source: mutated_source
      )

      call_count = 0
      allow(RSpec::Core::Runner).to receive(:run) do |_args, _out, _err|
        call_count += 1
        call_count == 1 ? 0 : 1
      end

      first_result = integration.call(passing_mutation)
      second_result = integration.call(failing_mutation)

      expect(first_result[:passed]).to be true
      expect(second_result[:passed]).to be false
      expect(call_count).to eq(2)
      # Ensure each call clears RSpec state
      expect(RSpec).to have_received(:clear_examples).twice
    end

    it "clears RSpec examples before each run" do
      allow(RSpec::Core::Runner).to receive(:run) do |_args, _out, _err|
        # Verify clear_examples was called before the runner executes
        expect(RSpec).to have_received(:clear_examples)
        0
      end

      integration.call(mutation)
    end

    it "clears RSpec state between runs" do
      allow(RSpec::Core::Runner).to receive(:run).and_return(0)

      integration.call(mutation)

      expect(RSpec).to have_received(:clear_examples)
    end

    it "clears instance variables from mutation-created ExampleGroups" do
      allow(RSpec::Core::Runner).to receive(:run) do |_args, _out, _err|
        # Simulate RSpec creating a new ExampleGroup during the run
        eg = Class.new(RSpec::Core::ExampleGroup)
        eg.instance_variable_set(:@retained_object, Object.new)
        0
      end

      integration.call(mutation)

      # All mutation-created EG classes should have ivars cleared
      ObjectSpace.each_object(Class) do |klass|
        next unless klass < RSpec::Core::ExampleGroup
        next if klass == RSpec::Core::AnonymousExampleGroup

        expect(klass.instance_variables).not_to include(:@retained_object)
      rescue TypeError
        nil
      end
    end

    # Snapshot-aware ExampleGroups constant removal (only constants added
    # during the run are removed, pre-existing host constants survive) is
    # covered end-to-end in spec/evilution/integration/rspec_host_isolation_spec.rb
    # and at the unit level in
    # spec/evilution/integration/rspec/state_guard/example_groups_constants_spec.rb.
    # The previous test here asserted the old blanket-clear behavior
    # (RSpec::ExampleGroups.remove_all_constants) which was the bug fixed by
    # the StateGuard refactor and is intentionally no longer used.

    it "propagates Evilution::Error raised by the framework loader" do
      failing_loader = instance_double(
        Evilution::Integration::RSpec::FrameworkLoader,
        loaded?: false
      )
      allow(failing_loader).to receive(:call).and_raise(
        Evilution::Error, "rspec-core is required but not available: cannot load such file -- rspec/core"
      )
      integration_no_rspec = described_class.new(
        test_files: ["spec/some_spec.rb"],
        framework_loader: failing_loader
      )

      expect { integration_no_rspec.call(mutation) }.to raise_error(Evilution::Error, /rspec-core is required/)
    end

    it "does not modify original file when framework loader raises" do
      failing_loader = instance_double(
        Evilution::Integration::RSpec::FrameworkLoader,
        loaded?: false
      )
      allow(failing_loader).to receive(:call).and_raise(Evilution::Error, "nope")
      integration_no_rspec = described_class.new(
        test_files: ["spec/some_spec.rb"],
        framework_loader: failing_loader
      )

      expect { integration_no_rspec.call(mutation) }.to raise_error(Evilution::Error)
      # Original file should never be touched (loader runs before mutation_applier)
      expect(File.read(source_file.path)).to eq(original_source)
    end
  end

  describe "temp file isolation" do
    let(:load_path_dir) { Dir.mktmpdir("evilution_lp") }
    let(:source_subpath) { "calculator.rb" }
    let(:source_path) { File.join(load_path_dir, source_subpath) }

    let(:lp_mutation) do
      double(
        "Mutation",
        file_path: source_path,
        original_source: original_source,
        mutated_source: mutated_source
      )
    end

    before do
      File.write(source_path, original_source)
      $LOAD_PATH.unshift(load_path_dir)
    end

    after do
      $LOAD_PATH.delete(load_path_dir)
      FileUtils.rm_rf(load_path_dir)
    end

    it "does not modify the original file on disk" do
      allow(RSpec::Core::Runner).to receive(:run).and_return(1)

      integration.call(lp_mutation)

      expect(File.read(source_path)).to eq(original_source)
    end

    it "leaves $LOAD_PATH unchanged across the call" do
      load_path_before = $LOAD_PATH.dup
      load_path_during = nil
      allow(RSpec::Core::Runner).to receive(:run) do |_args, _out, _err|
        load_path_during = $LOAD_PATH.dup
        1
      end

      integration.call(lp_mutation)

      expect(load_path_during).to eq(load_path_before)
      expect($LOAD_PATH).to eq(load_path_before)
    end

    it "preserves original file in $LOADED_FEATURES across the call" do
      original_feature = File.expand_path(source_path)
      $LOADED_FEATURES << original_feature

      allow(RSpec::Core::Runner).to receive(:run).and_return(1)

      integration.call(lp_mutation)

      expect($LOADED_FEATURES).to include(original_feature)
    ensure
      $LOADED_FEATURES.delete(original_feature)
    end
  end

  describe "Zeitwerk-like autoloader compatibility" do
    let(:autoload_dir) { Dir.mktmpdir("evilution_autoload") }
    let(:source_subpath) { "models/user.rb" }
    let(:autoload_source_path) { File.join(autoload_dir, source_subpath) }

    let(:autoload_original) { "class User\n  def name\n    'Alice'\n  end\nend\n" }
    let(:autoload_mutated) { "class User\n  def name\n    nil\n  end\nend\n" }

    let(:autoload_mutation) do
      double(
        "Mutation",
        file_path: autoload_source_path,
        original_source: autoload_original,
        mutated_source: autoload_mutated
      )
    end

    before do
      FileUtils.mkdir_p(File.dirname(autoload_source_path))
      File.write(autoload_source_path, autoload_original)
      # Simulate Zeitwerk: autoload dir is on $LOAD_PATH, file is in $LOADED_FEATURES
      $LOAD_PATH.unshift(autoload_dir)
      $LOADED_FEATURES << File.expand_path(autoload_source_path)
    end

    after do
      $LOAD_PATH.delete(autoload_dir)
      $LOADED_FEATURES.delete(File.expand_path(autoload_source_path))
      FileUtils.rm_rf(autoload_dir)
    end

    it "redefines the autoloaded class in memory without touching the original file" do
      value_during_run = nil
      allow(RSpec::Core::Runner).to receive(:run) do |_args, _out, _err|
        value_during_run = User.new.name
        1
      end

      load(autoload_source_path)
      integration.call(autoload_mutation)

      expect(value_during_run).to be_nil
      expect(File.read(autoload_source_path)).to eq(autoload_original)
    ensure
      Object.send(:remove_const, :User) if defined?(User)
    end

    it "does not modify the original autoloaded file" do
      file_during_run = nil
      allow(RSpec::Core::Runner).to receive(:run) do |_args, _out, _err|
        file_during_run = File.read(autoload_source_path)
        1
      end

      integration.call(autoload_mutation)

      expect(file_during_run).to eq(autoload_original)
    end

    it "preserves the original $LOADED_FEATURES entry after restore" do
      original_feature = File.expand_path(autoload_source_path)
      allow(RSpec::Core::Runner).to receive(:run).and_return(1)

      integration.call(autoload_mutation)

      expect($LOADED_FEATURES).to include(original_feature)
    end
  end

  describe "mutation isolation for non-LOAD_PATH files" do
    it "never modifies the original file during mutation" do
      file_content_during_run = nil
      allow(RSpec::Core::Runner).to receive(:run) do |_args, _out, _err|
        file_content_during_run = File.read(source_file.path)
        1
      end

      integration.call(mutation)

      expect(file_content_during_run).to eq(original_source)
    end
  end

  describe "test file selection" do
    it "uses provided test_files in build_args" do
      custom_integration = described_class.new(test_files: ["spec/foo_spec.rb", "spec/bar_spec.rb"])
      allow(RSpec::Core::Runner).to receive(:run) do |args, _out, _err|
        expect(args).to include("spec/foo_spec.rb", "spec/bar_spec.rb")
        0
      end

      custom_integration.call(mutation)
    end

    it "includes test_command in the result" do
      allow(RSpec::Core::Runner).to receive(:run).and_return(0)

      result = integration.call(mutation)

      expect(result[:test_command]).to eq("rspec --format progress --no-color --order defined spec/some_spec.rb")
    end

    it "includes default spec path in test_command when no test_files and fallback enabled" do
      default_integration = described_class.new(fallback_to_full_suite: true)
      allow(RSpec::Core::Runner).to receive(:run).and_return(0)

      result = default_integration.call(mutation)

      expect(result[:test_command]).to eq("rspec --format progress --no-color --order defined spec")
    end

    it "falls back to spec/ when no test_files and fallback enabled" do
      default_integration = described_class.new(fallback_to_full_suite: true)
      allow(RSpec::Core::Runner).to receive(:run) do |args, _out, _err|
        expect(args).to include("spec")
        expect(args).not_to include(nil)
        0
      end

      default_integration.call(mutation)
    end
  end

  describe "mutation_insert hooks" do
    it "fires mutation_insert_pre before applying mutation" do
      hooks = Evilution::Hooks::Registry.new
      events = []
      hooks.register(:mutation_insert_pre) { |payload| events << [:pre, payload[:mutation]] }
      hooked_integration = described_class.new(test_files: ["spec/some_spec.rb"], hooks: hooks)

      allow(RSpec::Core::Runner).to receive(:run) do |_args, _out, _err|
        events << [:run]
        0
      end

      hooked_integration.call(mutation)

      expect(events.first).to eq([:pre, mutation])
      expect(events[1]).to eq([:run])
    end

    it "fires mutation_insert_post after applying mutation and before running tests" do
      hooks = Evilution::Hooks::Registry.new
      events = []
      hooks.register(:mutation_insert_post) { |payload| events << [:post, payload[:mutation]] }
      hooked_integration = described_class.new(test_files: ["spec/some_spec.rb"], hooks: hooks)

      allow(RSpec::Core::Runner).to receive(:run) do |_args, _out, _err|
        events << [:run]
        0
      end

      hooked_integration.call(mutation)

      expect(events.first).to eq([:post, mutation])
      expect(events[1]).to eq([:run])
    end

    it "fires both hooks in correct order" do
      hooks = Evilution::Hooks::Registry.new
      events = []
      hooks.register(:mutation_insert_pre) { events << :pre }
      hooks.register(:mutation_insert_post) { events << :post }
      hooked_integration = described_class.new(test_files: ["spec/some_spec.rb"], hooks: hooks)

      allow(RSpec::Core::Runner).to receive(:run) do |_args, _out, _err|
        events << :run
        0
      end

      hooked_integration.call(mutation)

      expect(events).to eq(%i[pre post run])
    end

    it "provides file_path in hook payload" do
      hooks = Evilution::Hooks::Registry.new
      received_payload = nil
      hooks.register(:mutation_insert_pre) { |payload| received_payload = payload }
      hooked_integration = described_class.new(test_files: ["spec/some_spec.rb"], hooks: hooks)
      allow(RSpec::Core::Runner).to receive(:run).and_return(0)

      hooked_integration.call(mutation)

      expect(received_payload[:file_path]).to eq(mutation.file_path)
    end

    it "works without hooks (backwards compatible)" do
      no_hooks_integration = described_class.new(test_files: ["spec/some_spec.rb"])
      allow(RSpec::Core::Runner).to receive(:run).and_return(0)

      result = no_hooks_integration.call(mutation)

      expect(result[:passed]).to be true
    end
  end

  describe "setup_integration hooks" do
    # A fake framework loader that records when #call fires so tests can
    # observe ordering between setup_integration hooks and the actual load.
    let(:recording_loader_class) do
      Class.new do
        attr_reader :events

        def initialize(events)
          @events = events
          @loaded = false
        end

        def loaded?
          @loaded
        end

        def call
          @events << :load
          @loaded = true
        end
      end
    end

    it "fires setup_integration_pre before loading rspec" do
      hooks = Evilution::Hooks::Registry.new
      events = []
      hooks.register(:setup_integration_pre) { events << :setup_pre }
      loader = recording_loader_class.new(events)
      hooked_integration = described_class.new(
        test_files: ["spec/some_spec.rb"], hooks: hooks, framework_loader: loader
      )
      allow(RSpec::Core::Runner).to receive(:run).and_return(0)

      hooked_integration.call(mutation)

      expect(events[0]).to eq(:setup_pre)
      expect(events[1]).to eq(:load)
    end

    it "fires setup_integration_post after loading rspec" do
      hooks = Evilution::Hooks::Registry.new
      events = []
      hooks.register(:setup_integration_post) { events << :setup_post }
      loader = recording_loader_class.new(events)
      hooked_integration = described_class.new(
        test_files: ["spec/some_spec.rb"], hooks: hooks, framework_loader: loader
      )
      allow(RSpec::Core::Runner).to receive(:run).and_return(0)

      hooked_integration.call(mutation)

      expect(events[0]).to eq(:load)
      expect(events[1]).to eq(:setup_post)
    end

    it "fires both setup hooks in correct order" do
      hooks = Evilution::Hooks::Registry.new
      events = []
      hooks.register(:setup_integration_pre) { events << :setup_pre }
      hooks.register(:setup_integration_post) { events << :setup_post }
      loader = recording_loader_class.new(events)
      hooked_integration = described_class.new(
        test_files: ["spec/some_spec.rb"], hooks: hooks, framework_loader: loader
      )
      allow(RSpec::Core::Runner).to receive(:run).and_return(0)

      hooked_integration.call(mutation)

      expect(events).to eq(%i[setup_pre load setup_post])
    end

    it "provides integration type in hook payload" do
      hooks = Evilution::Hooks::Registry.new
      received = nil
      hooks.register(:setup_integration_pre) { |payload| received = payload }
      hooked_integration = described_class.new(test_files: ["spec/some_spec.rb"], hooks: hooks)
      allow(RSpec::Core::Runner).to receive(:run).and_return(0)

      hooked_integration.call(mutation)

      expect(received[:integration]).to eq(:rspec)
    end

    it "only fires setup hooks on first call" do
      hooks = Evilution::Hooks::Registry.new
      count = 0
      hooks.register(:setup_integration_pre) { count += 1 }
      hooked_integration = described_class.new(test_files: ["spec/some_spec.rb"], hooks: hooks)
      allow(RSpec::Core::Runner).to receive(:run).and_return(0)

      hooked_integration.call(mutation)
      hooked_integration.call(mutation)

      expect(count).to eq(1)
    end

    it "works without hooks (backwards compatible)" do
      loader = recording_loader_class.new([])
      no_hooks_integration = described_class.new(
        test_files: ["spec/some_spec.rb"], framework_loader: loader
      )
      allow(RSpec::Core::Runner).to receive(:run).and_return(0)

      result = no_hooks_integration.call(mutation)

      expect(result[:passed]).to be true
    end
  end

  describe "crash detection" do
    it "flags test_crashed with error detail when all failures are crashes" do
      detector = instance_double(Evilution::Integration::CrashDetector,
                                 only_crashes?: true,
                                 crash_summary: "NoMethodError (1 crash)",
                                 unique_crash_classes: ["NoMethodError"])
      allow(Evilution::Integration::CrashDetector).to receive(:new).and_return(detector)
      allow(detector).to receive(:example_failed)
      allow(RSpec.configuration).to receive(:add_formatter)
      allow(RSpec::Core::Runner).to receive(:run).and_return(1)

      result = integration.call(mutation)

      expect(result[:passed]).to be false
      expect(result[:test_crashed]).to be true
      expect(result[:error]).to include("test crashes")
      expect(result[:error]).to include("NoMethodError")
    end

    # Regression for EV-toid / GH #814: crashes that all share one class surface
    # that class via error_class so MutationExecutor can neutralize infra-only
    # crashes (ActiveRecord::StatementTimeout, Timeout::Error, etc.).
    it "sets error_class when all crashes share one class" do
      detector = instance_double(Evilution::Integration::CrashDetector,
                                 only_crashes?: true,
                                 crash_summary: "ActiveRecord::StatementTimeout (10 crashes)",
                                 unique_crash_classes: ["ActiveRecord::StatementTimeout"])
      allow(Evilution::Integration::CrashDetector).to receive(:new).and_return(detector)
      allow(detector).to receive(:example_failed)
      allow(RSpec.configuration).to receive(:add_formatter)
      allow(RSpec::Core::Runner).to receive(:run).and_return(1)

      result = integration.call(mutation)

      expect(result[:test_crashed]).to be true
      expect(result[:error_class]).to eq("ActiveRecord::StatementTimeout")
    end

    # When crashes are a mix of classes, we cannot attribute to a single class.
    # Leaving error_class nil keeps the result :killed (conservative — do not
    # false-neutralize when genuine mutation-caused crashes are present).
    it "omits error_class when crashes span multiple classes" do
      detector = instance_double(Evilution::Integration::CrashDetector,
                                 only_crashes?: true,
                                 crash_summary: "ActiveRecord::StatementTimeout, NoMethodError (2 crashes)",
                                 unique_crash_classes: %w[ActiveRecord::StatementTimeout NoMethodError])
      allow(Evilution::Integration::CrashDetector).to receive(:new).and_return(detector)
      allow(detector).to receive(:example_failed)
      allow(RSpec.configuration).to receive(:add_formatter)
      allow(RSpec::Core::Runner).to receive(:run).and_return(1)

      result = integration.call(mutation)

      expect(result[:test_crashed]).to be true
      expect(result[:error_class]).to be_nil
    end

    it "returns killed (no error) when failures include assertions" do
      detector = instance_double(Evilution::Integration::CrashDetector,
                                 only_crashes?: false)
      allow(Evilution::Integration::CrashDetector).to receive(:new).and_return(detector)
      allow(detector).to receive(:example_failed)
      allow(RSpec.configuration).to receive(:add_formatter)
      allow(RSpec::Core::Runner).to receive(:run).and_return(1)

      result = integration.call(mutation)

      expect(result[:passed]).to be false
      expect(result).not_to have_key(:error)
    end

    it "returns passed when tests pass regardless of detector" do
      detector = instance_double(Evilution::Integration::CrashDetector,
                                 only_crashes?: false)
      allow(Evilution::Integration::CrashDetector).to receive(:new).and_return(detector)
      allow(detector).to receive(:example_failed)
      allow(RSpec.configuration).to receive(:add_formatter)
      allow(RSpec::Core::Runner).to receive(:run).and_return(0)

      result = integration.call(mutation)

      expect(result[:passed]).to be true
    end
  end

  describe "related spec heuristic integration" do
    let(:selector) { instance_double(Evilution::SpecSelector) }
    let(:related_heuristic) { instance_double(Evilution::RelatedSpecHeuristic) }

    before do
      allow(Evilution::SpecSelector).to receive(:new).and_return(selector)
      allow(Evilution::RelatedSpecHeuristic).to receive(:new).and_return(related_heuristic)
    end

    it "appends related specs when heuristic returns matches and flag enabled" do
      allow(selector).to receive(:call).and_return(["spec/controllers/news_controller_spec.rb"])
      allow(related_heuristic).to receive(:call).and_return(["spec/requests/news_spec.rb"])
      auto_integration = described_class.new(related_specs_heuristic: true)
      allow(RSpec::Core::Runner).to receive(:run) do |args, _out, _err|
        expect(args).to include("spec/controllers/news_controller_spec.rb")
        expect(args).to include("spec/requests/news_spec.rb")
        0
      end

      auto_integration.call(mutation)
    end

    it "does not duplicate specs when related spec matches primary" do
      allow(selector).to receive(:call).and_return(["spec/requests/news_spec.rb"])
      allow(related_heuristic).to receive(:call).and_return(["spec/requests/news_spec.rb"])
      auto_integration = described_class.new(related_specs_heuristic: true)
      allow(RSpec::Core::Runner).to receive(:run) do |args, _out, _err|
        spec_args = args.select { |a| a.end_with?("_spec.rb") }
        expect(spec_args.length).to eq(1)
        0
      end

      auto_integration.call(mutation)
    end

    it "does not call related heuristic when explicit test_files provided" do
      allow(related_heuristic).to receive(:call)
      explicit = described_class.new(test_files: ["spec/explicit_spec.rb"], related_specs_heuristic: true)
      allow(RSpec::Core::Runner).to receive(:run).and_return(0)

      explicit.call(mutation)

      expect(related_heuristic).not_to have_received(:call)
    end

    it "works when heuristic returns empty array" do
      allow(selector).to receive(:call).and_return(["spec/news_spec.rb"])
      allow(related_heuristic).to receive(:call).and_return([])
      auto_integration = described_class.new(related_specs_heuristic: true)
      allow(RSpec::Core::Runner).to receive(:run) do |args, _out, _err|
        expect(args).to include("spec/news_spec.rb")
        0
      end

      auto_integration.call(mutation)
    end

    it "does not call related heuristic by default" do
      allow(selector).to receive(:call).and_return(["spec/controllers/news_controller_spec.rb"])
      allow(related_heuristic).to receive(:call)
      default_integration = described_class.new
      allow(RSpec::Core::Runner).to receive(:run) do |args, _out, _err|
        expect(args).to include("spec/controllers/news_controller_spec.rb")
        expect(args).not_to include("spec/requests/news_spec.rb")
        0
      end

      default_integration.call(mutation)

      expect(related_heuristic).not_to have_received(:call)
    end
  end

  describe "per-mutation spec targeting" do
    let(:selector) { instance_double(Evilution::SpecSelector) }

    before do
      allow(Evilution::SpecSelector).to receive(:new).and_return(selector)
    end

    it "uses resolved spec file for the mutation's source file" do
      allow(selector).to receive(:call).with(mutation.file_path).and_return(["spec/some_spec.rb"])
      auto_integration = described_class.new
      allow(RSpec::Core::Runner).to receive(:run) do |args, _out, _err|
        expect(args).to include("spec/some_spec.rb")
        expect(args).not_to include("spec")
        0
      end

      auto_integration.call(mutation)
    end

    it "returns an unresolved result when no matching spec is found (fail-fast default)" do
      allow(selector).to receive(:call).with(mutation.file_path).and_return(nil)
      auto_integration = described_class.new
      allow(RSpec::Core::Runner).to receive(:run)

      result = auto_integration.call(mutation)

      expect(result[:unresolved]).to be true
      expect(result[:passed]).to be false
      expect(result[:error]).to match(/no.*spec.*#{Regexp.escape(mutation.file_path)}/i)
      expect(RSpec::Core::Runner).not_to have_received(:run)
    end

    it "warns once per file when no matching spec is found" do
      allow(selector).to receive(:call).with(mutation.file_path).and_return(nil)
      auto_integration = described_class.new
      allow(RSpec::Core::Runner).to receive(:run).and_return(0)

      stderr = StringIO.new
      $stderr = stderr
      2.times { auto_integration.call(mutation) }
      $stderr = STDERR

      lines = stderr.string.lines.select { |l| l.include?("No matching spec") }
      expect(lines.size).to eq(1)
      expect(lines.first).to match(/#{Regexp.escape(mutation.file_path)}/)
      expect(lines.first).to include("marking mutation unresolved")
      expect(lines.first).not_to include("running full suite")
    end

    it "warns with full-suite wording when fallback_to_full_suite: true" do
      allow(selector).to receive(:call).with(mutation.file_path).and_return(nil)
      auto_integration = described_class.new(fallback_to_full_suite: true)
      allow(RSpec::Core::Runner).to receive(:run).and_return(0)

      stderr = StringIO.new
      $stderr = stderr
      auto_integration.call(mutation)
      $stderr = STDERR

      expect(stderr.string).to include("running full suite")
    end

    it "falls back to full spec suite when fallback_to_full_suite: true" do
      allow(selector).to receive(:call).with(mutation.file_path).and_return(nil)
      auto_integration = described_class.new(fallback_to_full_suite: true)
      allow(RSpec::Core::Runner).to receive(:run) do |args, _out, _err|
        expect(args).to include("spec")
        0
      end

      result = auto_integration.call(mutation)

      expect(result[:unresolved]).to be_falsey
      expect(RSpec::Core::Runner).to have_received(:run)
    end

    it "does not warn when spec is resolved successfully" do
      allow(selector).to receive(:call).with(mutation.file_path).and_return(["spec/some_spec.rb"])
      auto_integration = described_class.new
      allow(RSpec::Core::Runner).to receive(:run).and_return(0)

      expect { auto_integration.call(mutation) }.not_to output.to_stderr
    end

    it "does not use selector when explicit test_files are provided" do
      allow(selector).to receive(:call)
      explicit_integration = described_class.new(test_files: ["spec/explicit_spec.rb"])
      allow(RSpec::Core::Runner).to receive(:run).and_return(0)

      explicit_integration.call(mutation)

      expect(selector).not_to have_received(:call)
    end

    it "includes resolved spec in test_command" do
      allow(selector).to receive(:call).with(mutation.file_path).and_return(["spec/some_spec.rb"])
      auto_integration = described_class.new
      allow(RSpec::Core::Runner).to receive(:run).and_return(0)

      result = auto_integration.call(mutation)

      expect(result[:test_command]).to include("spec/some_spec.rb")
    end

    it "uses injected spec_selector when provided" do
      injected = instance_double(Evilution::SpecSelector)
      allow(injected).to receive(:call).with(mutation.file_path).and_return(["spec/injected_spec.rb"])
      integration = described_class.new(spec_selector: injected)
      allow(RSpec::Core::Runner).to receive(:run) do |args, _out, _err|
        expect(args).to include("spec/injected_spec.rb")
        0
      end

      integration.call(mutation)
    end
  end

  describe "example_filter wiring" do
    let(:example_filter) { instance_double(Evilution::ExampleFilter) }

    before { allow(Evilution).to receive(:const_defined?).and_call_original }

    it "passes locations (path:LINE) as rspec args when filter returns matches" do
      allow(example_filter).to receive(:call)
        .with(mutation, ["spec/some_spec.rb"])
        .and_return(["spec/some_spec.rb:12", "spec/some_spec.rb:34"])
      filtered = described_class.new(test_files: ["spec/some_spec.rb"], example_filter: example_filter)
      allow(RSpec::Core::Runner).to receive(:run) do |args, _out, _err|
        expect(args).to include("spec/some_spec.rb:12")
        expect(args).to include("spec/some_spec.rb:34")
        expect(args).not_to include("spec/some_spec.rb")
        0
      end

      filtered.call(mutation)
    end

    it "returns an unresolved result when filter returns nil" do
      allow(example_filter).to receive(:call).and_return(nil)
      filtered = described_class.new(test_files: ["spec/some_spec.rb"], example_filter: example_filter)
      allow(RSpec::Core::Runner).to receive(:run)

      result = filtered.call(mutation)

      expect(result[:unresolved]).to be true
      expect(result[:passed]).to be false
      expect(RSpec::Core::Runner).not_to have_received(:run)
    end

    it "distinguishes example-targeting nil from spec-resolver nil in the error message" do
      allow(example_filter).to receive(:call).and_return(nil)
      filtered = described_class.new(test_files: ["spec/some_spec.rb"], example_filter: example_filter)
      allow(RSpec::Core::Runner).to receive(:run)

      result = filtered.call(mutation)

      expect(result[:error]).to match(/no matching example/i)
      expect(result[:error]).not_to match(/no matching spec/i)
      expect(result[:test_command]).to match(/example/i)
    end

    it "falls back to plain spec paths when filter returns original spec_paths array" do
      allow(example_filter).to receive(:call)
        .with(mutation, ["spec/some_spec.rb"])
        .and_return(["spec/some_spec.rb"])
      filtered = described_class.new(test_files: ["spec/some_spec.rb"], example_filter: example_filter)
      allow(RSpec::Core::Runner).to receive(:run) do |args, _out, _err|
        expect(args).to include("spec/some_spec.rb")
        0
      end

      filtered.call(mutation)
    end

    it "preserves current behavior when no example_filter is injected" do
      no_filter = described_class.new(test_files: ["spec/some_spec.rb"])
      allow(RSpec::Core::Runner).to receive(:run) do |args, _out, _err|
        expect(args).to include("spec/some_spec.rb")
        0
      end

      no_filter.call(mutation)
    end

    it "does not invoke filter when resolve_test_files already returned nil (unresolved)" do
      selector = instance_double(Evilution::SpecSelector)
      allow(selector).to receive(:call).with(mutation.file_path).and_return(nil)
      allow(example_filter).to receive(:call)
      filtered = described_class.new(spec_selector: selector, example_filter: example_filter)
      allow(RSpec::Core::Runner).to receive(:run)

      filtered.call(mutation)

      expect(example_filter).not_to have_received(:call)
    end
  end

  describe "spec load path" do
    let(:spec_dir) { File.expand_path("spec") }
    let(:original_load_path) { $LOAD_PATH.dup }

    after { $LOAD_PATH.replace(original_load_path) }

    it "adds spec/ to $LOAD_PATH during ensure_framework_loaded" do
      $LOAD_PATH.delete(spec_dir)

      fresh = described_class.new(test_files: ["spec/some_spec.rb"])
      fresh.instance_variable_set(:@rspec_loaded, false)
      allow(RSpec::Core::Runner).to receive(:run).and_return(0)

      fresh.call(mutation)

      expect($LOAD_PATH).to include(spec_dir)
    end

    it "adds spec/ to $LOAD_PATH in baseline_runner" do
      $LOAD_PATH.delete(spec_dir)

      runner = described_class.baseline_runner
      allow(RSpec::Core::Runner).to receive(:run).and_return(0)

      runner.call("spec/some_spec.rb")

      expect($LOAD_PATH).to include(spec_dir)
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

    it "uses default spec_resolver" do
      options = described_class.baseline_options
      expect(options).not_to have_key(:spec_resolver)
    end
  end
end
