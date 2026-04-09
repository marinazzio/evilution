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

    it "removes ExampleGroup constants after each run" do
      allow(RSpec::Core::Runner).to receive(:run).and_return(0)
      allow(RSpec::ExampleGroups).to receive(:remove_all_constants)

      integration.call(mutation)

      expect(RSpec::ExampleGroups).to have_received(:remove_all_constants).at_least(:once)
    end

    it "raises Evilution::Error when rspec-core is not available" do
      integration_no_rspec = described_class.new(test_files: ["spec/some_spec.rb"])
      integration_no_rspec.instance_variable_set(:@rspec_loaded, false)
      allow(integration_no_rspec).to receive(:require).with("rspec/core").and_raise(LoadError, "cannot load such file -- rspec/core")

      expect { integration_no_rspec.call(mutation) }.to raise_error(Evilution::Error, /rspec-core is required/)
    end

    it "does not modify original file when ensure_rspec_loaded raises" do
      integration_no_rspec = described_class.new(test_files: ["spec/some_spec.rb"])
      integration_no_rspec.instance_variable_set(:@rspec_loaded, false)
      allow(integration_no_rspec).to receive(:require).with("rspec/core").and_raise(LoadError, "nope")

      expect { integration_no_rspec.call(mutation) }.to raise_error(Evilution::Error)
      # Original file should never be touched
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

    it "cleans up the temp directory after restore_original" do
      temp_dir_during_run = nil
      allow(RSpec::Core::Runner).to receive(:run) do |_args, _out, _err|
        # Capture the temp dir that was prepended to $LOAD_PATH
        temp_dir_during_run = $LOAD_PATH.first
        expect(Dir.exist?(temp_dir_during_run)).to be true
        1
      end

      integration.call(lp_mutation)

      expect(temp_dir_during_run).not_to be_nil
      expect(Dir.exist?(temp_dir_during_run)).to be false
    end

    it "prepends temp dir to $LOAD_PATH during test execution" do
      allow(RSpec::Core::Runner).to receive(:run) do |_args, _out, _err|
        # The first $LOAD_PATH entry should be our temp dir
        expect($LOAD_PATH.first).to start_with(File.join(Dir.tmpdir, "evilution"))
        0
      end

      integration.call(lp_mutation)

      # After restore, temp dir should not be in $LOAD_PATH
      evilution_entries = $LOAD_PATH.select { |p| p.include?("evilution") && p.start_with?(Dir.tmpdir) && p != load_path_dir }
      expect(evilution_entries).to be_empty
    end

    it "picks the most specific LOAD_PATH match for nested entries" do
      nested_dir = File.join(load_path_dir, "core")
      FileUtils.mkdir_p(nested_dir)
      nested_source = File.join(nested_dir, "widget.rb")
      File.write(nested_source, original_source)
      # Push nested_dir AFTER load_path_dir so the broader match comes first
      $LOAD_PATH.push(nested_dir)

      nested_mutation = double(
        "Mutation",
        file_path: nested_source,
        original_source: original_source,
        mutated_source: mutated_source
      )

      shadow_subpath = nil
      allow(RSpec::Core::Runner).to receive(:run) do |_args, _out, _err|
        temp_dir = integration.instance_variable_get(:@temp_dir)
        temp_files = Dir.glob(File.join(temp_dir, "**", "*.rb"))
        # Should be just "widget.rb", not "core/widget.rb"
        shadow_subpath = temp_files.first.delete_prefix("#{temp_dir}/")
        1
      end

      integration.call(nested_mutation)

      expect(shadow_subpath).to eq("widget.rb")
    ensure
      $LOAD_PATH.delete(nested_dir)
    end

    it "removes original file from $LOADED_FEATURES during mutation" do
      # Simulate the file being already loaded (e.g., transitively required)
      original_feature = File.expand_path(source_path)
      $LOADED_FEATURES << original_feature

      loaded_features_during_run = nil
      allow(RSpec::Core::Runner).to receive(:run) do |_args, _out, _err|
        loaded_features_during_run = $LOADED_FEATURES.dup
        1
      end

      integration.call(lp_mutation)

      expect(loaded_features_during_run).not_to include(original_feature)
    ensure
      $LOADED_FEATURES.delete(original_feature)
    end

    it "restores original file to $LOADED_FEATURES after mutation" do
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

    it "shadows the autoloaded file so require picks up the mutation" do
      required_path = nil
      allow(RSpec::Core::Runner).to receive(:run) do |_args, _out, _err|
        # Simulate what happens when a spec requires the file:
        # With displaced feature, require should find the shadow
        temp_dir = $LOAD_PATH.first
        shadow = File.join(temp_dir, source_subpath)
        required_path = shadow if File.exist?(shadow)
        1
      end

      integration.call(autoload_mutation)

      expect(required_path).not_to be_nil
      expect(File.read(autoload_source_path)).to eq(autoload_original)
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

    it "writes mutated content to the shadow path matching the subpath" do
      shadow_content = nil
      allow(RSpec::Core::Runner).to receive(:run) do |_args, _out, _err|
        temp_dir = integration.instance_variable_get(:@temp_dir)
        shadow = File.join(temp_dir, source_subpath)
        shadow_content = File.read(shadow) if File.exist?(shadow)
        1
      end

      integration.call(autoload_mutation)

      expect(shadow_content).to eq(autoload_mutated)
    end
  end

  describe "temp file isolation for non-LOAD_PATH files" do
    it "never modifies the original file during mutation" do
      file_content_during_run = nil
      allow(RSpec::Core::Runner).to receive(:run) do |_args, _out, _err|
        file_content_during_run = File.read(source_file.path)
        1
      end

      integration.call(mutation)

      expect(file_content_during_run).to eq(original_source)
    end

    it "writes mutated source to a temp file" do
      temp_file_content = nil
      allow(RSpec::Core::Runner).to receive(:run) do |_args, _out, _err|
        temp_dir = integration.instance_variable_get(:@temp_dir)
        temp_files = Dir.glob(File.join(temp_dir, "**", "*.rb"))
        temp_file_content = File.read(temp_files.first) if temp_files.any?
        1
      end

      integration.call(mutation)

      expect(temp_file_content).to eq(mutated_source)
    end

    it "cleans up temp directory after the call" do
      temp_dir_during_run = nil
      allow(RSpec::Core::Runner).to receive(:run) do |_args, _out, _err|
        temp_dir_during_run = integration.instance_variable_get(:@temp_dir)
        expect(Dir.exist?(temp_dir_during_run)).to be true
        1
      end

      integration.call(mutation)

      expect(temp_dir_during_run).not_to be_nil
      expect(Dir.exist?(temp_dir_during_run)).to be false
    end

    it "cleans up temp directory even when runner raises" do
      temp_dir_during_run = nil
      allow(RSpec::Core::Runner).to receive(:run) do |_args, _out, _err|
        temp_dir_during_run = integration.instance_variable_get(:@temp_dir)
        raise "boom"
      end

      integration.call(mutation)

      expect(temp_dir_during_run).not_to be_nil
      expect(Dir.exist?(temp_dir_during_run)).to be false
    end

    it "loads the mutated temp file to redefine the class" do
      loaded_file = nil
      allow(integration).to receive(:load).and_wrap_original do |_method, path, *_args|
        loaded_file = path
      end
      allow(RSpec::Core::Runner).to receive(:run).and_return(1)

      integration.call(mutation)

      expect(loaded_file).not_to be_nil
      expect(loaded_file).to start_with(Dir.tmpdir)
      expect(loaded_file).to end_with(File.expand_path(source_file.path))
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

    it "includes default spec path in test_command when no test_files" do
      default_integration = described_class.new
      allow(RSpec::Core::Runner).to receive(:run).and_return(0)

      result = default_integration.call(mutation)

      expect(result[:test_command]).to eq("rspec --format progress --no-color --order defined spec")
    end

    it "defaults to spec/ when no test_files provided" do
      default_integration = described_class.new
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
    it "fires setup_integration_pre before loading rspec" do
      hooks = Evilution::Hooks::Registry.new
      events = []
      hooks.register(:setup_integration_pre) { events << :setup_pre }
      hooked_integration = described_class.new(test_files: ["spec/some_spec.rb"], hooks: hooks)
      hooked_integration.instance_variable_set(:@rspec_loaded, false)

      allow(hooked_integration).to receive(:require).with("rspec/core") do
        events << :require
        # Simulate successful load
      end
      allow(RSpec::Core::Runner).to receive(:run).and_return(0)

      hooked_integration.call(mutation)

      expect(events[0]).to eq(:setup_pre)
      expect(events[1]).to eq(:require)
    end

    it "fires setup_integration_post after loading rspec" do
      hooks = Evilution::Hooks::Registry.new
      events = []
      hooks.register(:setup_integration_post) { events << :setup_post }
      hooked_integration = described_class.new(test_files: ["spec/some_spec.rb"], hooks: hooks)
      hooked_integration.instance_variable_set(:@rspec_loaded, false)

      allow(hooked_integration).to receive(:require).with("rspec/core") do
        events << :require
      end
      allow(RSpec::Core::Runner).to receive(:run).and_return(0)

      hooked_integration.call(mutation)

      expect(events[0]).to eq(:require)
      expect(events[1]).to eq(:setup_post)
    end

    it "fires both setup hooks in correct order" do
      hooks = Evilution::Hooks::Registry.new
      events = []
      hooks.register(:setup_integration_pre) { events << :setup_pre }
      hooks.register(:setup_integration_post) { events << :setup_post }
      hooked_integration = described_class.new(test_files: ["spec/some_spec.rb"], hooks: hooks)
      hooked_integration.instance_variable_set(:@rspec_loaded, false)

      allow(hooked_integration).to receive(:require).with("rspec/core")
      allow(RSpec::Core::Runner).to receive(:run).and_return(0)

      hooked_integration.call(mutation)

      expect(events).to eq(%i[setup_pre setup_post])
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
      no_hooks_integration = described_class.new(test_files: ["spec/some_spec.rb"])
      no_hooks_integration.instance_variable_set(:@rspec_loaded, false)
      allow(no_hooks_integration).to receive(:require).with("rspec/core")
      allow(RSpec::Core::Runner).to receive(:run).and_return(0)

      result = no_hooks_integration.call(mutation)

      expect(result[:passed]).to be true
    end
  end

  describe "crash detection" do
    it "returns error when all test failures are crashes" do
      detector = instance_double(Evilution::Integration::CrashDetector,
                                 only_crashes?: true,
                                 crash_summary: "NoMethodError (1 crash)")
      allow(Evilution::Integration::CrashDetector).to receive(:new).and_return(detector)
      allow(detector).to receive(:example_failed)
      allow(RSpec.configuration).to receive(:add_formatter)
      allow(RSpec::Core::Runner).to receive(:run).and_return(1)

      result = integration.call(mutation)

      expect(result[:passed]).to be false
      expect(result[:error]).to include("test crashes")
      expect(result[:error]).to include("NoMethodError")
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
    let(:resolver) { instance_double(Evilution::SpecResolver) }
    let(:related_heuristic) { instance_double(Evilution::RelatedSpecHeuristic) }

    before do
      allow(Evilution::SpecResolver).to receive(:new).and_return(resolver)
      allow(Evilution::RelatedSpecHeuristic).to receive(:new).and_return(related_heuristic)
    end

    it "appends related specs when heuristic returns matches" do
      allow(resolver).to receive(:call).and_return("spec/controllers/news_controller_spec.rb")
      allow(related_heuristic).to receive(:call).and_return(["spec/requests/news_spec.rb"])
      auto_integration = described_class.new
      allow(RSpec::Core::Runner).to receive(:run) do |args, _out, _err|
        expect(args).to include("spec/controllers/news_controller_spec.rb")
        expect(args).to include("spec/requests/news_spec.rb")
        0
      end

      auto_integration.call(mutation)
    end

    it "does not duplicate specs when related spec matches primary" do
      allow(resolver).to receive(:call).and_return("spec/requests/news_spec.rb")
      allow(related_heuristic).to receive(:call).and_return(["spec/requests/news_spec.rb"])
      auto_integration = described_class.new
      allow(RSpec::Core::Runner).to receive(:run) do |args, _out, _err|
        spec_args = args.select { |a| a.end_with?("_spec.rb") }
        expect(spec_args.length).to eq(1)
        0
      end

      auto_integration.call(mutation)
    end

    it "does not call related heuristic when explicit test_files provided" do
      allow(related_heuristic).to receive(:call)
      explicit = described_class.new(test_files: ["spec/explicit_spec.rb"])
      allow(RSpec::Core::Runner).to receive(:run).and_return(0)

      explicit.call(mutation)

      expect(related_heuristic).not_to have_received(:call)
    end

    it "works when heuristic returns empty array" do
      allow(resolver).to receive(:call).and_return("spec/news_spec.rb")
      allow(related_heuristic).to receive(:call).and_return([])
      auto_integration = described_class.new
      allow(RSpec::Core::Runner).to receive(:run) do |args, _out, _err|
        expect(args).to include("spec/news_spec.rb")
        0
      end

      auto_integration.call(mutation)
    end
  end

  describe "per-mutation spec targeting" do
    let(:resolver) { instance_double(Evilution::SpecResolver) }

    before do
      allow(Evilution::SpecResolver).to receive(:new).and_return(resolver)
    end

    it "uses resolved spec file for the mutation's source file" do
      allow(resolver).to receive(:call).with(mutation.file_path).and_return("spec/some_spec.rb")
      auto_integration = described_class.new
      allow(RSpec::Core::Runner).to receive(:run) do |args, _out, _err|
        expect(args).to include("spec/some_spec.rb")
        expect(args).not_to include("spec")
        0
      end

      auto_integration.call(mutation)
    end

    it "falls back to full spec suite when no matching spec found" do
      allow(resolver).to receive(:call).with(mutation.file_path).and_return(nil)
      auto_integration = described_class.new
      allow(RSpec::Core::Runner).to receive(:run) do |args, _out, _err|
        expect(args).to include("spec")
        0
      end

      auto_integration.call(mutation)
    end

    it "warns once per file when falling back to full spec suite" do
      allow(resolver).to receive(:call).with(mutation.file_path).and_return(nil)
      auto_integration = described_class.new
      allow(RSpec::Core::Runner).to receive(:run).and_return(0)

      stderr = StringIO.new
      $stderr = stderr
      2.times { auto_integration.call(mutation) }
      $stderr = STDERR

      lines = stderr.string.lines.select { |l| l.include?("No matching spec") }
      expect(lines.size).to eq(1)
      expect(lines.first).to match(/#{Regexp.escape(mutation.file_path)}/)
    end

    it "does not warn when spec is resolved successfully" do
      allow(resolver).to receive(:call).with(mutation.file_path).and_return("spec/some_spec.rb")
      auto_integration = described_class.new
      allow(RSpec::Core::Runner).to receive(:run).and_return(0)

      expect { auto_integration.call(mutation) }.not_to output.to_stderr
    end

    it "does not use resolver when explicit test_files are provided" do
      allow(resolver).to receive(:call)
      explicit_integration = described_class.new(test_files: ["spec/explicit_spec.rb"])
      allow(RSpec::Core::Runner).to receive(:run).and_return(0)

      explicit_integration.call(mutation)

      expect(resolver).not_to have_received(:call)
    end

    it "includes resolved spec in test_command" do
      allow(resolver).to receive(:call).with(mutation.file_path).and_return("spec/some_spec.rb")
      auto_integration = described_class.new
      allow(RSpec::Core::Runner).to receive(:run).and_return(0)

      result = auto_integration.call(mutation)

      expect(result[:test_command]).to include("spec/some_spec.rb")
    end
  end

  describe ".baseline_runner" do
    it "returns a callable" do
      expect(described_class.baseline_runner).to respond_to(:call)
    end
  end
end
