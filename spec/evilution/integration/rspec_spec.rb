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
      # Ensure each call clears RSpec world state independently
      expect(RSpec).to have_received(:reset).twice
    end

    it "calls RSpec.reset before each run to clear world state" do
      allow(RSpec::Core::Runner).to receive(:run) do |_args, _out, _err|
        # Verify reset was called before the runner executes
        expect(RSpec).to have_received(:reset)
        0
      end

      integration.call(mutation)
    end

    it "resets RSpec between runs" do
      allow(RSpec::Core::Runner).to receive(:run).and_return(0)

      integration.call(mutation)

      expect(RSpec).to have_received(:reset)
    end

    it "raises Evilution::Error when rspec-core is not available" do
      integration_no_rspec = described_class.new(test_files: ["spec/some_spec.rb"])
      integration_no_rspec.instance_variable_set(:@rspec_loaded, false)
      allow(integration_no_rspec).to receive(:require).with("rspec/core").and_raise(LoadError, "cannot load such file -- rspec/core")

      expect { integration_no_rspec.call(mutation) }.to raise_error(Evilution::Error, /rspec-core is required/)
    end

    it "does not write stale content when ensure_rspec_loaded raises" do
      integration_no_rspec = described_class.new(test_files: ["spec/some_spec.rb"])
      integration_no_rspec.instance_variable_set(:@rspec_loaded, false)
      allow(integration_no_rspec).to receive(:require).with("rspec/core").and_raise(LoadError, "nope")

      # Simulate a previous call having set @original_content
      integration_no_rspec.instance_variable_set(:@original_content, "stale content")

      expect { integration_no_rspec.call(mutation) }.to raise_error(Evilution::Error)
      # File should NOT have been overwritten with stale content
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

    it "does not use resolver when explicit test_files are provided" do
      explicit_integration = described_class.new(test_files: ["spec/explicit_spec.rb"])
      allow(RSpec::Core::Runner).to receive(:run).and_return(0)

      explicit_integration.call(mutation)

      expect(Evilution::SpecResolver).not_to have_received(:new)
    end

    it "includes resolved spec in test_command" do
      allow(resolver).to receive(:call).with(mutation.file_path).and_return("spec/some_spec.rb")
      auto_integration = described_class.new
      allow(RSpec::Core::Runner).to receive(:run).and_return(0)

      result = auto_integration.call(mutation)

      expect(result[:test_command]).to include("spec/some_spec.rb")
    end
  end
end
