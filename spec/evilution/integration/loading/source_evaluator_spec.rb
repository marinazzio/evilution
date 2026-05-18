# frozen_string_literal: true

require "tmpdir"
require "fileutils"
require "evilution/integration/loading/source_evaluator"

RSpec.describe Evilution::Integration::Loading::SourceEvaluator do
  subject(:evaluator) { described_class.new }

  let(:project_dir) { Dir.mktmpdir("evilution_source_evaluator") }
  let(:file_path) { File.join(project_dir, "target.rb") }

  after do
    FileUtils.rm_rf(project_dir)
  end

  describe "#call" do
    it "evaluates the source so its side effects take effect" do
      evaluator.call("EvilutionSourceEvaluatorFlag = :evaluated", file_path)

      expect(EvilutionSourceEvaluatorFlag).to eq(:evaluated)
    ensure
      Object.send(:remove_const, :EvilutionSourceEvaluatorFlag) if defined?(EvilutionSourceEvaluatorFlag)
    end

    it "returns the value of the evaluated expression" do
      expect(evaluator.call("40 + 2", file_path)).to eq(42)
    end

    it "evaluates with __FILE__ set to the absolute path of file_path" do
      result = evaluator.call("__FILE__", "target.rb")

      expect(result).to eq(File.expand_path("target.rb"))
    end

    it "resolves a relative file_path to an absolute path for __dir__" do
      result = evaluator.call("__dir__", file_path)

      expect(result).to eq(project_dir)
    end

    it "raises when the source itself is invalid Ruby rather than silently skipping eval" do
      expect { evaluator.call("def broken(", file_path) }.to raise_error(SyntaxError)
    end
  end
end
