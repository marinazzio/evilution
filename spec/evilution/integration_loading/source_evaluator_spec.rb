# frozen_string_literal: true

require "tempfile"
require "evilution/integration/loading/source_evaluator"

RSpec.describe Evilution::Integration::Loading::SourceEvaluator do
  subject(:evaluator) { described_class.new }

  describe "#call" do
    it "evaluates source at TOPLEVEL_BINDING" do
      evaluator.call("module EvilutionEvalToplevel; X = 42; end\n", "/tmp/fake.rb")

      expect(EvilutionEvalToplevel::X).to eq(42)
    ensure
      Object.send(:remove_const, :EvilutionEvalToplevel) if defined?(EvilutionEvalToplevel)
    end

    it "uses the absolute path so __dir__ / require_relative resolve against real source" do
      Dir.mktmpdir("evilution_src_eval") do |dir|
        sibling = File.join(dir, "sibling.rb")
        File.write(sibling, "module EvilutionEvalSibling; V = :ok; end\n")
        target = File.join(dir, "target.rb")
        source = "require_relative 'sibling'\nmodule EvilutionEvalTarget; VAL = EvilutionEvalSibling::V; end\n"

        evaluator.call(source, target)

        expect(EvilutionEvalTarget::VAL).to eq(:ok)
      ensure
        Object.send(:remove_const, :EvilutionEvalTarget) if defined?(EvilutionEvalTarget)
        Object.send(:remove_const, :EvilutionEvalSibling) if defined?(EvilutionEvalSibling)
      end
    end

    it "expands a relative path to absolute before evaluating" do
      evaluator.call("module EvilutionEvalAbs; FILE = __FILE__; end\n", "some/relative/path.rb")

      expect(EvilutionEvalAbs::FILE).to eq(File.expand_path("some/relative/path.rb"))
    ensure
      Object.send(:remove_const, :EvilutionEvalAbs) if defined?(EvilutionEvalAbs)
    end

    it "propagates syntax errors as SyntaxError" do
      expect { evaluator.call("def foo\n", "/tmp/x.rb") }.to raise_error(SyntaxError)
    end

    it "propagates runtime errors" do
      expect { evaluator.call("raise 'boom'\n", "/tmp/x.rb") }.to raise_error(RuntimeError, "boom")
    end
  end
end
