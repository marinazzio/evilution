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

    it "defaults to nearest spec/ directory when no convention match" do
      rel_mutation = double(
        "Mutation",
        file_path: "app/models/user.rb",
        original_source: original_source,
        mutated_source: mutated_source
      )
      allow(File).to receive(:read).with("app/models/user.rb").and_return(original_source)
      allow(File).to receive(:write)

      integration_default = described_class.new
      allow(Dir).to receive(:exist?).and_return(false)
      allow(File).to receive(:exist?).and_return(false)

      # The walk-up from expanded path will find spec/ at project root
      expanded_spec = File.join(File.expand_path("."), "spec")
      allow(Dir).to receive(:exist?).with(expanded_spec).and_return(true)

      expect(RSpec::Core::Runner).to receive(:run) do |args, _out, _err|
        expect(args).to include(expanded_spec)
        0
      end

      integration_default.call(rel_mutation)
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

    it "maps absolute /path/lib/foo.rb to /path/spec/foo_spec.rb" do
      abs_mutation = double(
        "Mutation",
        file_path: "/tmp/project/lib/calculator.rb",
        original_source: original_source,
        mutated_source: mutated_source
      )
      allow(File).to receive(:read).with("/tmp/project/lib/calculator.rb").and_return(original_source)
      allow(File).to receive(:write)
      allow(File).to receive(:exist?).and_return(false)
      allow(File).to receive(:exist?).with("/tmp/project/spec/calculator_spec.rb").and_return(true)

      expect(RSpec::Core::Runner).to receive(:run) do |args, _out, _err|
        expect(args).to include("/tmp/project/spec/calculator_spec.rb")
        0
      end

      integration_auto.call(abs_mutation)
    end

    it "falls back to project spec/ dir for absolute paths when no convention match" do
      abs_mutation = double(
        "Mutation",
        file_path: "/tmp/project/lib/calculator.rb",
        original_source: original_source,
        mutated_source: mutated_source
      )
      allow(File).to receive(:read).with("/tmp/project/lib/calculator.rb").and_return(original_source)
      allow(File).to receive(:write)
      allow(File).to receive(:exist?).and_return(false)
      allow(Dir).to receive(:exist?).with("/tmp/project/spec").and_return(true)

      expect(RSpec::Core::Runner).to receive(:run) do |args, _out, _err|
        expect(args).to include("/tmp/project/spec")
        0
      end

      integration_auto.call(abs_mutation)
    end

    it "walks up directories to find spec/ for absolute paths not under lib/" do
      app_mutation = double(
        "Mutation",
        file_path: "/tmp/project/app/models/user.rb",
        original_source: original_source,
        mutated_source: mutated_source
      )
      allow(File).to receive(:read).with("/tmp/project/app/models/user.rb").and_return(original_source)
      allow(File).to receive(:write)
      allow(File).to receive(:exist?).and_return(false)
      allow(Dir).to receive(:exist?).and_return(false)
      allow(Dir).to receive(:exist?).with("/tmp/project/app/models/spec").and_return(false)
      allow(Dir).to receive(:exist?).with("/tmp/project/app/spec").and_return(false)
      allow(Dir).to receive(:exist?).with("/tmp/project/spec").and_return(true)

      expect(RSpec::Core::Runner).to receive(:run) do |args, _out, _err|
        expect(args).to include("/tmp/project/spec")
        0
      end

      integration_auto.call(app_mutation)
    end

    it "walks up directories to find spec/ for relative paths in different subtrees" do
      relative_mutation = double(
        "Mutation",
        file_path: "tmp/project/app/models/user.rb",
        original_source: original_source,
        mutated_source: mutated_source
      )
      allow(File).to receive(:read).with("tmp/project/app/models/user.rb").and_return(original_source)
      allow(File).to receive(:write)
      allow(File).to receive(:exist?).and_return(false)
      allow(Dir).to receive(:exist?).and_return(false)

      # The walk-up will check each parent; stub the one that matches
      expected_spec = File.join(File.expand_path("tmp/project"), "spec")
      allow(Dir).to receive(:exist?).with(expected_spec).and_return(true)

      expect(RSpec::Core::Runner).to receive(:run) do |args, _out, _err|
        expect(args).to include(expected_spec)
        0
      end

      integration_auto.call(relative_mutation)
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
