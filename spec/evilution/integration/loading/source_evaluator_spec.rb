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

    # Regression for EV-vlbh / GH #1191: SourceEvaluator anchors the eval
    # __FILE__ against PROJECT_ROOT only when Evilution.in_isolated_worker?
    # is set (EV-wqxu / GH #1278 sandbox flag). The flag's two branches
    # produce observably different __FILE__ values, so a single ternary
    # mutation collapses one branch into the other.
    describe "isolated-worker anchoring" do
      around do |example|
        previous = Evilution.instance_variable_get(:@in_isolated_worker)
        example.run
      ensure
        Evilution.instance_variable_set(:@in_isolated_worker, previous)
      end

      it "anchors __FILE__ to Dir.pwd when the isolated-worker flag is unset" do
        Dir.mktmpdir do |sandbox|
          Dir.chdir(sandbox) do
            expect(evaluator.call("__FILE__", "target.rb")).to eq(File.join(sandbox, "target.rb"))
          end
        end
      end

      it "anchors __FILE__ to Evilution::PROJECT_ROOT when the isolated-worker flag is set" do
        Evilution.in_isolated_worker!

        Dir.mktmpdir do |sandbox|
          Dir.chdir(sandbox) do
            expect(evaluator.call("__FILE__", "target.rb"))
              .to eq(File.join(Evilution::PROJECT_ROOT, "target.rb"))
          end
        end
      end
    end
  end
end
