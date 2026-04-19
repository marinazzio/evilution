# frozen_string_literal: true

require "evilution/reporter/cli"
require "evilution/result/mutation_result"
require "evilution/result/summary"

RSpec.describe Evilution::Reporter::CLI do
  subject(:reporter) { described_class.new }

  let(:survived_mutation) do
    subj = double("Subject", name: "User#check")
    double(
      "Mutation",
      operator_name: "comparison_replacement",
      file_path: "lib/user.rb",
      line: 9,
      diff: "- x >= 10\n+ x > 10",
      original_slice: "x >= 10\n",
      mutated_slice: "x > 10\n",
      subject: subj
    )
  end

  let(:killed_mutation) do
    double(
      "Mutation",
      operator_name: "comparison_replacement",
      file_path: "lib/user.rb",
      line: 5,
      diff: "- x == 10\n+ x != 10",
      original_slice: "x == 10\n",
      mutated_slice: "x != 10\n"
    )
  end

  let(:survived_result) do
    Evilution::Result::MutationResult.new(
      mutation: survived_mutation,
      status: :survived,
      duration: 0.123
    )
  end

  let(:killed_result) do
    Evilution::Result::MutationResult.new(
      mutation: killed_mutation,
      status: :killed,
      duration: 0.456
    )
  end

  let(:summary) do
    Evilution::Result::Summary.new(
      results: [survived_result, killed_result],
      duration: 12.34
    )
  end

  describe "#call" do
    it "includes the version in the header" do
      output = reporter.call(summary)

      expect(output).to include("Evilution v#{Evilution::VERSION}")
    end

    it "includes a separator line" do
      output = reporter.call(summary)

      expect(output).to include("=" * 44)
    end

    it "shows correct mutation counts" do
      output = reporter.call(summary)

      expect(output).to include("2 total")
      expect(output).to include("1 killed")
      expect(output).to include("1 survived")
      expect(output).to include("0 timed out")
    end

    it "shows the score as a percentage with fraction" do
      output = reporter.call(summary)

      expect(output).to include("Score:")
      expect(output).to include("50.00%")
      expect(output).to include("(1/2)")
    end

    it "shows the duration in seconds" do
      output = reporter.call(summary)

      expect(output).to include("Duration: 12.34s")
    end

    it "shows efficiency metrics" do
      output = reporter.call(summary)

      expect(output).to match(%r{Efficiency: \d+\.\d+% killtime, \d+\.\d+ mutations/s})
    end

    it "calculates correct efficiency values" do
      r1 = Evilution::Result::MutationResult.new(mutation: killed_mutation, status: :killed, duration: 3.0)
      r2 = Evilution::Result::MutationResult.new(mutation: survived_mutation, status: :survived, duration: 2.0)
      s = Evilution::Result::Summary.new(results: [r1, r2], duration: 10.0)

      output = reporter.call(s)

      expect(output).to include("Efficiency: 50.00% killtime, 0.20 mutations/s")
    end

    it "omits efficiency line when duration is zero" do
      s = Evilution::Result::Summary.new(results: [killed_result], duration: 0.0)

      output = reporter.call(s)

      expect(output).not_to include("Efficiency:")
    end

    it "lists survived mutations with operator and location" do
      output = reporter.call(summary)

      expect(output).to include("Survived mutations (1 coverage gap):")
      expect(output).to include("comparison_replacement: lib/user.rb:9")
    end

    it "shows the subject name for survived mutations" do
      output = reporter.call(summary)

      expect(output).to include("User#check")
    end

    it "shows a git-style unified diff header for survived mutations" do
      output = reporter.call(summary)

      expect(output).to include("--- a/lib/user.rb")
      expect(output).to include("+++ b/lib/user.rb")
      expect(output).to include("@@ -9,1 +9,1 @@")
    end

    it "shows the diff body for survived mutations in unified format" do
      output = reporter.call(summary)

      expect(output).to include("-x >= 10")
      expect(output).to include("+x > 10")
    end

    it "indents the unified diff under the gap header" do
      output = reporter.call(summary)

      expect(output).to match(%r{^ {4}--- a/lib/user\.rb$})
      expect(output).to match(/^ {4}@@ -9,1 \+9,1 @@$/)
    end

    context "with multi-line slices" do
      let(:survived_mutation) do
        subj = double("Subject", name: "User#check")
        double(
          "Mutation",
          operator_name: "block_removal",
          file_path: "lib/user.rb",
          line: 12,
          diff: "ignored",
          original_slice: "if cond\n  do_a\nend\n",
          mutated_slice: "if cond\n  do_b\nend\n",
          subject: subj
        )
      end

      it "emits hunk lengths matching slice line counts" do
        output = reporter.call(summary)

        expect(output).to include("@@ -12,3 +12,3 @@")
      end

      it "renders unchanged lines as context with leading space" do
        output = reporter.call(summary)

        expect(output).to include(" if cond")
        expect(output).to include("-  do_a")
        expect(output).to include("+  do_b")
        expect(output).to include(" end")
      end
    end

    context "when slices are nil (legacy mutation)" do
      let(:survived_mutation) do
        subj = double("Subject", name: "User#check")
        double(
          "Mutation",
          operator_name: "comparison_replacement",
          file_path: "lib/user.rb",
          line: 9,
          diff: "- x >= 10\n+ x > 10",
          original_slice: nil,
          mutated_slice: nil,
          subject: subj
        )
      end

      it "falls back to legacy diff format" do
        output = reporter.call(summary)

        expect(output).to include("- x >= 10")
        expect(output).to include("+ x > 10")
        expect(output).not_to include("@@")
      end
    end

    it "shows FAIL when score is below threshold" do
      output = reporter.call(summary)

      # score is 50%, below default 80% threshold
      expect(output).to include("Result: FAIL")
    end

    it "shows PASS when score meets threshold" do
      passing_summary = Evilution::Result::Summary.new(
        results: [killed_result],
        duration: 0.5
      )
      output = reporter.call(passing_summary)

      expect(output).to include("Result: PASS")
    end

    it "includes the threshold percentage in the result line" do
      output = reporter.call(summary)

      expect(output).to include("80.00%")
    end

    context "with multiple survived mutations on the same line" do
      let(:survived_mutation2) do
        subj = double("Subject", name: "User#check")
        double(
          "Mutation",
          operator_name: "method_call_removal",
          file_path: "lib/user.rb",
          line: 9,
          diff: "- x >= 10\n+ nil",
          subject: subj
        )
      end

      let(:survived_result2) do
        Evilution::Result::MutationResult.new(
          mutation: survived_mutation2,
          status: :survived,
          duration: 0.2
        )
      end

      let(:grouped_summary) do
        Evilution::Result::Summary.new(
          results: [survived_result, survived_result2, killed_result],
          duration: 1.0
        )
      end

      it "groups them into a single coverage gap" do
        output = reporter.call(grouped_summary)

        expect(output).to include("Survived mutations (1 coverage gap):")
      end

      it "shows the count and operators for grouped gaps" do
        output = reporter.call(grouped_summary)

        expect(output).to include("[2 mutations: comparison_replacement, method_call_removal]")
      end

      it "shows the location and subject for grouped gaps" do
        output = reporter.call(grouped_summary)

        expect(output).to include("lib/user.rb:9 (User#check)")
      end
    end

    it "does not show survived mutations section when there are none" do
      passing_summary = Evilution::Result::Summary.new(
        results: [killed_result],
        duration: 0.5
      )
      output = reporter.call(passing_summary)

      expect(output).not_to include("Survived mutations")
    end

    context "with neutral mutations" do
      let(:neutral_mutation) do
        double(
          "Mutation",
          operator_name: "comparison_replacement",
          file_path: "lib/user.rb",
          line: 12,
          diff: "- x <= 5\n+ x < 5"
        )
      end

      let(:neutral_result) do
        Evilution::Result::MutationResult.new(
          mutation: neutral_mutation,
          status: :neutral,
          duration: 0.1
        )
      end

      let(:neutral_summary) do
        Evilution::Result::Summary.new(
          results: [killed_result, neutral_result],
          duration: 1.0
        )
      end

      it "includes neutral count in mutations line" do
        output = reporter.call(neutral_summary)

        expect(output).to include("1 neutral")
      end

      it "shows neutral mutations section" do
        output = reporter.call(neutral_summary)

        expect(output).to include("Neutral mutations (test already failing):")
        expect(output).to include("comparison_replacement: lib/user.rb:12")
      end

      it "excludes neutrals from score denominator" do
        output = reporter.call(neutral_summary)

        expect(output).to include("Score:")
        expect(output).to include("(1/1)")
      end

      it "does not show neutral section when there are none" do
        output = reporter.call(summary)

        expect(output).not_to include("Neutral mutations")
      end
    end

    context "with unresolved mutations" do
      let(:unresolved_mutation) do
        double(
          "Mutation",
          operator_name: "integer_literal",
          file_path: "lib/isolated.rb",
          line: 42,
          diff: "- 1\n+ 2"
        )
      end

      let(:unresolved_result) do
        Evilution::Result::MutationResult.new(
          mutation: unresolved_mutation,
          status: :unresolved,
          duration: 0.0
        )
      end

      let(:unresolved_summary) do
        Evilution::Result::Summary.new(
          results: [killed_result, unresolved_result],
          duration: 1.0
        )
      end

      it "shows unresolved mutations section" do
        output = reporter.call(unresolved_summary)

        expect(output).to include("Unresolved mutations (no spec resolved):")
        expect(output).to include("integer_literal: lib/isolated.rb:42")
      end

      it "does not show unresolved section when there are none" do
        output = reporter.call(summary)

        expect(output).not_to include("Unresolved mutations")
      end
    end

    it "handles empty results gracefully" do
      empty_summary = Evilution::Result::Summary.new(results: [], duration: 0.0)
      output = reporter.call(empty_summary)

      expect(output).to include("0 total")
      expect(output).to include("0 killed")
      expect(output).to include("0 survived")
      expect(output).not_to include("Survived mutations")
    end

    it "shows truncation notice when summary is truncated" do
      truncated_summary = Evilution::Result::Summary.new(
        results: [survived_result],
        duration: 0.5,
        truncated: true
      )
      output = reporter.call(truncated_summary)

      expect(output).to include("[TRUNCATED] Stopped early due to --fail-fast")
    end

    it "does not show truncation notice when summary is not truncated" do
      output = reporter.call(summary)

      expect(output).not_to include("TRUNCATED")
    end

    context "with skipped mutations" do
      let(:skipped_summary) do
        Evilution::Result::Summary.new(
          results: [killed_result],
          duration: 1.0,
          skipped: 3
        )
      end

      it "includes skipped count in mutations line" do
        output = reporter.call(skipped_summary)

        expect(output).to include("3 skipped")
      end

      it "does not show skipped when count is zero" do
        output = reporter.call(summary)

        expect(output).not_to include("skipped")
      end
    end

    context "with disabled mutations" do
      let(:disabled_mutation) do
        double(
          "Mutation",
          operator_name: "boolean_literal_replacement",
          file_path: "lib/user.rb",
          line: 15
        )
      end

      let(:disabled_summary) do
        Evilution::Result::Summary.new(
          results: [killed_result],
          duration: 1.0,
          disabled_mutations: [disabled_mutation]
        )
      end

      it "shows disabled mutations section" do
        output = reporter.call(disabled_summary)

        expect(output).to include("Disabled mutations (skipped by # evilution:disable):")
        expect(output).to include("boolean_literal_replacement: lib/user.rb:15")
      end

      it "does not show disabled section when empty" do
        output = reporter.call(summary)

        expect(output).not_to include("Disabled mutations")
      end
    end

    context "with errored mutations" do
      let(:error_result) do
        Evilution::Result::MutationResult.new(
          mutation: killed_mutation,
          status: :error,
          duration: 0.05,
          error_message: "syntax error in mutated source: unexpected token"
        )
      end

      let(:error_summary) do
        Evilution::Result::Summary.new(
          results: [killed_result, error_result],
          duration: 1.0
        )
      end

      it "shows errored mutations section with error message" do
        output = reporter.call(error_summary)

        expect(output).to include("Errored mutations:")
        expect(output).to include("comparison_replacement: lib/user.rb:5")
        expect(output).to include("syntax error in mutated source: unexpected token")
      end

      it "does not show errored section when empty" do
        output = reporter.call(summary)

        expect(output).not_to include("Errored mutations")
      end

      it "indents every line of a multi-line error message" do
        multiline_result = Evilution::Result::MutationResult.new(
          mutation: killed_mutation,
          status: :error,
          duration: 0.05,
          error_message: "syntax error line 1\nunexpected token line 2\nand line 3"
        )
        multiline_summary = Evilution::Result::Summary.new(
          results: [multiline_result],
          duration: 1.0
        )

        output = reporter.call(multiline_summary)

        expect(output).to include("    syntax error line 1")
        expect(output).to include("    unexpected token line 2")
        expect(output).to include("    and line 3")
      end
    end
  end
end
