# frozen_string_literal: true

require "evilution/integration/loading/mutation_applier"

RSpec.describe Evilution::Integration::Loading::MutationApplier do
  let(:validator) { instance_double("validator", call: nil) }
  let(:pinner) { instance_double("pinner", call: []) }
  let(:cleaner) { instance_double("cleaner", call: nil) }
  let(:evaluator) { instance_double("evaluator", call: nil) }
  let(:recovery) { ->(_src, &blk) { blk.call } }

  subject(:applier) do
    described_class.new(
      syntax_validator: validator,
      constant_pinner: pinner,
      concern_state_cleaner: cleaner,
      source_evaluator: evaluator,
      redefinition_recovery: recovery
    )
  end

  let(:mutation) do
    double(
      "Mutation",
      file_path: "/tmp/foo.rb",
      original_source: "class Foo; end\n",
      mutated_source: "class Bar; end\n"
    )
  end

  describe "#call" do
    it "returns nil on successful apply" do
      expect(applier.call(mutation)).to be_nil
    end

    it "invokes collaborators in the documented order" do
      calls = []
      v = Object.new
      v.define_singleton_method(:call) do |src|
        calls << [:validate, src]
        nil
      end
      p = Object.new
      p.define_singleton_method(:call) do |src|
        calls << [:pin, src]
        []
      end
      c = Object.new
      c.define_singleton_method(:call) { |fp| calls << [:clean, fp] }
      e = Object.new
      e.define_singleton_method(:call) { |src, fp| calls << [:eval, src, fp] }
      r = lambda do |src, &blk|
        calls << [:recovery_open, src]
        blk.call
        calls << [:recovery_close]
      end

      described_class.new(
        syntax_validator: v, constant_pinner: p, concern_state_cleaner: c,
        source_evaluator: e, redefinition_recovery: r
      ).call(mutation)

      expect(calls.map(&:first)).to eq(%i[validate pin clean recovery_open eval recovery_close])
    end

    it "returns validator's error hash and stops when source is invalid" do
      err = { passed: false, error: "mutated source has syntax errors" }
      v = ->(_src) { err }

      expect(pinner).not_to receive(:call)
      expect(cleaner).not_to receive(:call)
      expect(evaluator).not_to receive(:call)

      result = described_class.new(
        syntax_validator: v, constant_pinner: pinner, concern_state_cleaner: cleaner,
        source_evaluator: evaluator, redefinition_recovery: recovery
      ).call(mutation)

      expect(result).to eq(err)
    end

    it "pins using original_source and cleans using file_path" do
      expect(pinner).to receive(:call).with(mutation.original_source)
      expect(cleaner).to receive(:call).with(mutation.file_path)
      expect(evaluator).to receive(:call).with(mutation.mutated_source, mutation.file_path)

      applier.call(mutation)
    end

    it "wraps SyntaxError into a failure result" do
      failing_eval = Object.new
      failing_eval.define_singleton_method(:call) { |_src, _fp| raise SyntaxError, "bad" }

      result = described_class.new(
        syntax_validator: validator, constant_pinner: pinner, concern_state_cleaner: cleaner,
        source_evaluator: failing_eval, redefinition_recovery: recovery
      ).call(mutation)

      expect(result[:passed]).to be false
      expect(result[:error]).to include("syntax error in mutated source")
      expect(result[:error_class]).to eq("SyntaxError")
    end

    it "wraps ScriptError / StandardError with class and backtrace" do
      failing_eval = Object.new
      failing_eval.define_singleton_method(:call) { |_src, _fp| raise ArgumentError, "nope" }

      result = described_class.new(
        syntax_validator: validator, constant_pinner: pinner, concern_state_cleaner: cleaner,
        source_evaluator: failing_eval, redefinition_recovery: ->(_src, &blk) { blk.call }
      ).call(mutation)

      expect(result[:passed]).to be false
      expect(result[:error]).to eq("ArgumentError: nope")
      expect(result[:error_class]).to eq("ArgumentError")
      expect(result[:error_backtrace]).to be_an(Array)
    end
  end
end
