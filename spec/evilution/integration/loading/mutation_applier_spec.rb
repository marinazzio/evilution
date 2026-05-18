# frozen_string_literal: true

require "tmpdir"
require "fileutils"
require "evilution/integration/loading/mutation_applier"

RSpec.describe Evilution::Integration::Loading::MutationApplier do
  subject(:applier) { described_class.new }

  let(:project_dir) { Dir.mktmpdir("evilution_applier") }
  let(:lib_dir) { File.join(project_dir, "lib") }
  let(:source_path) { File.join(lib_dir, "widget.rb") }
  let(:part_path) { File.join(lib_dir, "widget", "part.rb") }

  let(:original_source) do
    <<~RUBY
      class EkaxClobberWidget
        def self.value
          1
        end
      end
      require_relative "widget/part"
    RUBY
  end

  let(:mutated_source) { original_source.sub("    1", "    2") }

  let(:mutation) do
    double(
      "Mutation",
      file_path: source_path,
      original_source: original_source,
      mutated_source: mutated_source
    )
  end

  before do
    FileUtils.mkdir_p(File.join(lib_dir, "widget"))
    File.write(source_path, original_source)
    # Sibling that requires the parent file back — the pattern that triggers
    # the self-clobber: a lazy-loaded file whose own body re-`require`s itself
    # transitively through a sibling.
    File.write(part_path, %(require_relative "../widget"\n))
  end

  after do
    FileUtils.rm_rf(project_dir)
    Object.send(:remove_const, :EkaxClobberWidget) if Object.const_defined?(:EkaxClobberWidget)
    [source_path, part_path].each do |p|
      real = File.realpath(File.expand_path(p))
      $LOADED_FEATURES.delete(real)
    rescue Errno::ENOENT
      nil
    end
  end

  it "applies the mutation even when the file's own require_relative chain " \
     "loops back to it before it is registered in $LOADED_FEATURES" do
    applier.call(mutation)

    expect(EkaxClobberWidget.value).to eq(2)
  end

  describe "#call with injected collaborators" do
    let(:validator) { instance_double("validator", call: nil) }
    let(:pinner) { instance_double("pinner", call: []) }
    let(:cleaner) { instance_double("cleaner", call: nil) }
    let(:evaluator) { instance_double("evaluator", call: nil) }
    let(:recovery) { ->(_src, &blk) { blk.call } }

    let(:injected_applier) do
      described_class.new(
        syntax_validator: validator,
        constant_pinner: pinner,
        concern_state_cleaner: cleaner,
        source_evaluator: evaluator,
        redefinition_recovery: recovery
      )
    end

    let(:injected_mutation) do
      double(
        "Mutation",
        file_path: "/tmp/evilution_applier_nonexistent.rb",
        original_source: "class Foo; end\n",
        mutated_source: "class Bar; end\n",
        eval_source: "class Baz; end\n"
      )
    end

    it "returns nil on a successful apply" do
      expect(injected_applier.call(injected_mutation)).to be_nil
    end

    it "returns nil on success even when the evaluator returns a truthy value" do
      noisy_evaluator = instance_double("evaluator", call: "evaluator return value")

      result = described_class.new(
        syntax_validator: validator, constant_pinner: pinner,
        concern_state_cleaner: cleaner, source_evaluator: noisy_evaluator,
        redefinition_recovery: recovery
      ).call(injected_mutation)

      expect(result).to be_nil
    end

    it "returns the validator's error result and skips applying when source is invalid" do
      error = { passed: false, error: "mutated source has syntax errors" }
      allow(validator).to receive(:call).and_return(error)

      expect(pinner).not_to receive(:call)
      expect(cleaner).not_to receive(:call)
      expect(evaluator).not_to receive(:call)

      expect(injected_applier.call(injected_mutation)).to eq(error)
    end

    it "evaluates mutation.eval_source when the mutation responds to it" do
      seen = nil
      tracking_evaluator = Object.new
      tracking_evaluator.define_singleton_method(:call) { |src, _fp| seen = src }

      described_class.new(
        syntax_validator: validator, constant_pinner: pinner,
        concern_state_cleaner: cleaner, source_evaluator: tracking_evaluator,
        redefinition_recovery: recovery
      ).call(injected_mutation)

      expect(seen).to eq("class Baz; end\n")
    end

    it "evaluates mutation.mutated_source when the mutation has no eval_source" do
      no_eval = double(
        "Mutation",
        file_path: "/tmp/evilution_applier_nonexistent.rb",
        original_source: "class Foo; end\n",
        mutated_source: "class Bar; end\n"
      )
      seen = nil
      tracking_evaluator = Object.new
      tracking_evaluator.define_singleton_method(:call) { |src, _fp| seen = src }

      described_class.new(
        syntax_validator: validator, constant_pinner: pinner,
        concern_state_cleaner: cleaner, source_evaluator: tracking_evaluator,
        redefinition_recovery: recovery
      ).call(no_eval)

      expect(seen).to eq("class Bar; end\n")
    end

    it "passes the eval target itself, not the mutation object, to the evaluator" do
      seen = :unset
      tracking_evaluator = Object.new
      tracking_evaluator.define_singleton_method(:call) { |src, _fp| seen = src }

      described_class.new(
        syntax_validator: validator, constant_pinner: pinner,
        concern_state_cleaner: cleaner, source_evaluator: tracking_evaluator,
        redefinition_recovery: recovery
      ).call(injected_mutation)

      expect(seen).to be_a(String)
    end

    it "pins constants from the mutation's original_source" do
      expect(pinner).to receive(:call).with("class Foo; end\n")

      injected_applier.call(injected_mutation)
    end

    it "cleans concern state for the mutation's file_path" do
      expect(cleaner).to receive(:call).with("/tmp/evilution_applier_nonexistent.rb")

      injected_applier.call(injected_mutation)
    end

    it "wraps a SyntaxError into a failure result with its message" do
      failing = Object.new
      failing.define_singleton_method(:call) do |_src, _fp|
        raise SyntaxError, "unexpected token"
      end

      result = described_class.new(
        syntax_validator: validator, constant_pinner: pinner,
        concern_state_cleaner: cleaner, source_evaluator: failing,
        redefinition_recovery: recovery
      ).call(injected_mutation)

      expect(result).to include(passed: false, error_class: "SyntaxError")
      expect(result[:error]).to eq("syntax error in mutated source: unexpected token")
    end

    it "wraps a StandardError prefixing the error class name" do
      failing = Object.new
      failing.define_singleton_method(:call) { |_src, _fp| raise ArgumentError, "nope" }

      result = described_class.new(
        syntax_validator: validator, constant_pinner: pinner,
        concern_state_cleaner: cleaner, source_evaluator: failing,
        redefinition_recovery: recovery
      ).call(injected_mutation)

      expect(result[:error]).to eq("ArgumentError: nope")
      expect(result[:error_class]).to eq("ArgumentError")
    end

    it "builds a failure result hash with passed, error, class and backtrace keys" do
      failing = Object.new
      failing.define_singleton_method(:call) { |_src, _fp| raise ArgumentError, "boom" }

      result = described_class.new(
        syntax_validator: validator, constant_pinner: pinner,
        concern_state_cleaner: cleaner, source_evaluator: failing,
        redefinition_recovery: recovery
      ).call(injected_mutation)

      expect(result).to be_a(Hash)
      expect(result.keys).to contain_exactly(
        :passed, :error, :error_class, :error_backtrace
      )
      expect(result[:passed]).to be(false)
      expect(result[:error_backtrace]).to be_an(Array)
    end
  end
end
