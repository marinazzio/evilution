# frozen_string_literal: true

require "evilution/feedback/setup_warning"
require "evilution/result/summary"
require "evilution/result/mutation_result"
require "evilution/result/error_info"

RSpec.describe Evilution::Feedback::SetupWarning do
  def errored_result(error_class:)
    instance_double(
      Evilution::Result::MutationResult,
      status: :error,
      error?: true,
      killed?: false,
      survived?: false,
      timeout?: false,
      neutral?: false,
      equivalent?: false,
      unresolved?: false,
      unparseable?: false,
      error_class: error_class
    )
  end

  def killed_result
    instance_double(
      Evilution::Result::MutationResult,
      status: :killed,
      error?: false,
      killed?: true,
      survived?: false,
      timeout?: false,
      neutral?: false,
      equivalent?: false,
      unresolved?: false,
      unparseable?: false,
      error_class: nil
    )
  end

  def summary_with(results)
    instance_double(
      Evilution::Result::Summary,
      results: results,
      total: results.size,
      errors: results.count(&:error?)
    )
  end

  describe ".call" do
    it "returns nil when there are no results" do
      expect(described_class.call(summary_with([]))).to be_nil
    end

    it "returns nil when summary is nil" do
      expect(described_class.call(nil)).to be_nil
    end

    it "returns nil when most mutations did not error" do
      results = Array.new(8) { killed_result } + Array.new(2) { errored_result(error_class: "NameError") }
      expect(described_class.call(summary_with(results))).to be_nil
    end

    it "returns a NameError-specific hint when all mutations errored with NameError" do
      results = Array.new(10) { errored_result(error_class: "NameError") }
      message = described_class.call(summary_with(results))
      expect(message).to include("NameError")
      expect(message).to include("preload")
      expect(message).to include("Rails")
      expect(message).to include("mutations errored")
      expect(message).not_to match(/workers errored/i)
    end

    it "returns a LoadError-specific hint when all mutations errored with LoadError" do
      results = Array.new(10) { errored_result(error_class: "LoadError") }
      message = described_class.call(summary_with(results))
      expect(message).to include("LoadError")
      expect(message).to include("preload")
    end

    it "returns a generic hint when all mutations errored with an unmapped class" do
      results = Array.new(10) { errored_result(error_class: "Foo::CustomError") }
      message = described_class.call(summary_with(results))
      expect(message).to include("Foo::CustomError")
      expect(message).to include("10 / 10")
    end

    it "returns nil when errored mutations span many distinct classes (no dominant pattern)" do
      results = [
        errored_result(error_class: "NameError"),
        errored_result(error_class: "ArgumentError"),
        errored_result(error_class: "NoMethodError"),
        errored_result(error_class: "RuntimeError"),
        errored_result(error_class: "TypeError")
      ]
      expect(described_class.call(summary_with(results))).to be_nil
    end

    it "triggers when 80% of mutations errored with the same class even if a few killed" do
      results = Array.new(8) { errored_result(error_class: "NameError") } + Array.new(2) { killed_result }
      message = described_class.call(summary_with(results))
      expect(message).to include("NameError")
    end

    it "ignores errored mutations with nil error_class when checking dominance" do
      results = [errored_result(error_class: nil)] * 10
      expect(described_class.call(summary_with(results))).to be_nil
    end

    it "computes the dominant cluster over errored results only, excluding killed ones" do
      # 8 NameError + 2 LoadError errors + 2 killed (total 12).
      # errors/total = 10/12 clears the dominance threshold.
      # Over the 10 errored results NameError clusters at 8/10 = 0.8 -> hint.
      # If killed results were folded in, the denominator becomes 12 and
      # 8/12 = 0.67 falls below the threshold -> no warning.
      results = Array.new(8) { errored_result(error_class: "NameError") } +
                Array.new(2) { errored_result(error_class: "LoadError") } +
                Array.new(2) { killed_result }
      message = described_class.call(summary_with(results))
      expect(message).to include("NameError")
    end

    it "uses float division so a 90% cluster still triggers a warning" do
      # 9 NameError + 1 LoadError: 9/10 = 0.9 float ratio clears the 0.8
      # threshold. Integer division (9 / 10 == 0) would suppress the warning.
      results = Array.new(9) { errored_result(error_class: "NameError") } +
                [errored_result(error_class: "LoadError")]
      message = described_class.call(summary_with(results))
      expect(message).to include("NameError")
    end
  end

  describe "dominant error class detection" do
    it "identifies the dominant class when it clusters past the threshold" do
      errored = Array.new(9) { errored_result(error_class: "NameError") } +
                [errored_result(error_class: "LoadError")]
      expect(described_class.send(:dominant_error_class, errored)).to eq("NameError")
    end

    # EV-unar / GH #1299 — kill survivors from EV-j2kz 2026-05-30 baseline.

    # Line 44: `return nil if errored_results.empty?` — direct unit test on the
    # private method asserts exact-nil return when given an empty array.
    it "returns nil from dominant_error_class for empty errored_results" do
      expect(described_class.send(:dominant_error_class, [])).to be_nil
    end

    # Line 49: `return nil if counts.empty?` — when all errored results have
    # nil error_class, counts remain empty and the method returns nil.
    it "returns nil from dominant_error_class when all errored have nil error_class" do
      errored = Array.new(5) { errored_result(error_class: nil) }
      expect(described_class.send(:dominant_error_class, errored)).to be_nil
    end

    # Line 52: `<` strict — boundary at exactly 0.8 ratio. Strict-less keeps
    # the class when ratio == 0.8; `<=` would discard it.
    it "returns the dominant class when ratio equals the threshold exactly" do
      # 8 NameError of 10 errored = 0.8 == ERROR_CLASS_CLUSTER_THRESHOLD
      errored = Array.new(8) { errored_result(error_class: "NameError") } +
                Array.new(2) { errored_result(error_class: "LoadError") }
      expect(described_class.send(:dominant_error_class, errored)).to eq("NameError")
    end

    # Line 52 — ratios below the threshold return nil (no dominant class).
    it "returns nil when no class clusters above the threshold" do
      # 5 NameError of 10 = 0.5 < 0.8 → no dominant class
      errored = Array.new(5) { errored_result(error_class: "NameError") } +
                Array.new(5) { errored_result(error_class: "LoadError") }
      expect(described_class.send(:dominant_error_class, errored)).to be_nil
    end
  end

  describe ".call (specific hint substring assertions)" do
    # Line 74: `when "LoadError"` mutated to `when ""`. The generic-template
    # message contains "LoadError" via interpolation, so just `include` is too
    # loose. Assert hint-specific phrases that appear only in LOAD_ERROR_HINT
    # (and assert the generic-template phrase does NOT appear).
    it "returns the LoadError hint (not the generic template) when klass is LoadError" do
      results = Array.new(10) { errored_result(error_class: "LoadError") }
      message = described_class.call(summary_with(results))

      # LOAD_ERROR_HINT-specific phrase:
      expect(message).to include("A `require` in the mutated source")
      # Generic template phrase that must NOT appear:
      expect(message).not_to include("The mutation score reflects this setup failure")
    end

    # Line 73 equivalent — same approach for NameError, killing the
    # `when "NameError"` removal mutation.
    it "returns the NameError hint (not the generic template) when klass is NameError" do
      results = Array.new(10) { errored_result(error_class: "NameError") }
      message = described_class.call(summary_with(results))

      # NAME_ERROR_HINT-specific phrase:
      expect(message).to include("autoloaded constants")
      # Generic template phrase that must NOT appear:
      expect(message).not_to include("The mutation score reflects this setup failure")
    end

    # Line 75 — generic template phrase appears for unmapped classes.
    it "returns the generic template hint for unmapped error classes" do
      results = Array.new(10) { errored_result(error_class: "Foo::Custom") }
      message = described_class.call(summary_with(results))

      # Generic template phrase:
      expect(message).to include("The mutation score reflects this setup failure")
      # Specific-hint phrases must NOT appear:
      expect(message).not_to include("autoloaded constants")
      expect(message).not_to include("A `require` in the mutated source")
    end
  end
end
