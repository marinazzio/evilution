# frozen_string_literal: true

require "evilution/reporter/html"
require "evilution/result/mutation_result"
require "evilution/result/summary"

RSpec.describe Evilution::Reporter::HTML do
  subject(:reporter) { described_class.new }

  let(:survived_mutation) do
    subj = double("Subject", name: "User#check")
    double(
      "Mutation",
      operator_name: "comparison_replacement",
      file_path: "lib/user.rb",
      line: 9,
      column: 4,
      diff: "- x >= 10\n+ x > 10",
      subject: subj
    )
  end

  let(:killed_mutation) do
    double(
      "Mutation",
      operator_name: "boolean_literal_replacement",
      file_path: "lib/user.rb",
      line: 5,
      column: 8,
      diff: "- true\n+ false"
    )
  end

  let(:killed_mutation_other_file) do
    double(
      "Mutation",
      operator_name: "string_literal",
      file_path: "lib/account.rb",
      line: 12,
      column: 2,
      diff: '- "hello"\n+ ""'
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

  let(:killed_result_other_file) do
    Evilution::Result::MutationResult.new(
      mutation: killed_mutation_other_file,
      status: :killed,
      duration: 0.200
    )
  end

  let(:summary) do
    Evilution::Result::Summary.new(
      results: [survived_result, killed_result],
      duration: 0.6
    )
  end

  describe "#call" do
    it "returns a valid HTML document" do
      output = reporter.call(summary)

      expect(output).to include("<!DOCTYPE html>")
      expect(output).to include("<html")
      expect(output).to include("</html>")
    end

    it "includes the version" do
      output = reporter.call(summary)

      expect(output).to include(Evilution::VERSION)
    end

    it "includes summary statistics" do
      output = reporter.call(summary)

      expect(output).to match(%r{Total</span></div>.*}m)
      expect(output).to match(%r{<span class="card-value">2</span><span class="card-label">Total</span>})
      expect(output).to match(%r{<span class="card-value">1</span><span class="card-label">Killed</span>})
      expect(output).to include("50.00%")
    end

    it "includes survived mutations with diffs" do
      output = reporter.call(summary)

      expect(output).to include("Coverage Gaps (1)")
      expect(output).to include("comparison_replacement")
      expect(output).to include("lib/user.rb")
      expect(output).to include("x &gt;= 10")
      expect(output).to include("x &gt; 10")
    end

    context "with multiple survived mutations on the same line" do
      let(:survived_mutation2) do
        subj = double("Subject", name: "User#check")
        double(
          "Mutation",
          operator_name: "method_call_removal",
          file_path: "lib/user.rb",
          line: 9,
          column: 4,
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

      it "renders a grouped coverage gap" do
        output = reporter.call(grouped_summary)

        expect(output).to include("Coverage Gaps (1)")
        expect(output).to include("coverage-gap")
        expect(output).to include("gap-header")
        expect(output).to include("2 mutations")
      end

      it "shows operator tags in grouped gap" do
        output = reporter.call(grouped_summary)

        expect(output).to include("operator-tag")
        expect(output).to include("comparison_replacement")
        expect(output).to include("method_call_removal")
      end
    end

    it "includes suggestion for survived mutations" do
      output = reporter.call(summary)

      expect(output).to include("boundary condition")
    end

    it "groups mutations by file in sorted order" do
      multi_file_summary = Evilution::Result::Summary.new(
        results: [survived_result, killed_result, killed_result_other_file],
        duration: 0.8
      )
      output = reporter.call(multi_file_summary)

      expect(output).to include("lib/user.rb")
      expect(output).to include("lib/account.rb")
      account_pos = output.index("lib/account.rb")
      user_pos = output.index("lib/user.rb")
      expect(account_pos).to be < user_pos
    end

    it "color-codes lines by mutation status" do
      output = reporter.call(summary)

      expect(output).to include("survived")
      expect(output).to include("killed")
    end

    it "handles empty results" do
      empty_summary = Evilution::Result::Summary.new(results: [], duration: 0.0)
      output = reporter.call(empty_summary)

      expect(output).to include("<!DOCTYPE html>")
      expect(output).to match(%r{<span class="card-value">0</span><span class="card-label">Total</span>})
      expect(output).to include("No mutations generated.")
    end

    it "includes meta tags and title" do
      output = reporter.call(summary)

      expect(output).to include('charset="UTF-8"')
      expect(output).to include("viewport")
      expect(output).to include("<title>Evilution Mutation Report</title>")
    end

    it "includes inline CSS" do
      output = reporter.call(summary)

      expect(output).to include("<style")
    end

    it "does not depend on external resources" do
      output = reporter.call(summary)

      expect(output).not_to include("http://")
      expect(output).not_to include("https://")
    end

    context "with neutral mutations" do
      let(:neutral_mutation) do
        double(
          "Mutation",
          operator_name: "integer_literal",
          file_path: "lib/user.rb",
          line: 15,
          column: 0,
          diff: "- 0\n+ 1"
        )
      end

      let(:neutral_result) do
        Evilution::Result::MutationResult.new(
          mutation: neutral_mutation,
          status: :neutral,
          duration: 0.1
        )
      end

      it "shows neutral mutations" do
        neutral_summary = Evilution::Result::Summary.new(
          results: [killed_result, neutral_result],
          duration: 0.6
        )
        output = reporter.call(neutral_summary)

        expect(output).to include("neutral")
      end
    end

    context "with unresolved mutations" do
      let(:unresolved_mutation) do
        double(
          "Mutation",
          operator_name: "integer_literal",
          file_path: "lib/user.rb",
          line: 15,
          column: 0,
          diff: "- 0\n+ 1"
        )
      end

      let(:unresolved_result) do
        Evilution::Result::MutationResult.new(
          mutation: unresolved_mutation,
          status: :unresolved,
          duration: 0.0
        )
      end

      it "shows unresolved card" do
        unresolved_summary = Evilution::Result::Summary.new(
          results: [killed_result, unresolved_result],
          duration: 0.6
        )
        output = reporter.call(unresolved_summary)

        expect(output).to include("Unresolved")
      end

      it "renders an unresolved details section listing operator and location" do
        unresolved_summary = Evilution::Result::Summary.new(
          results: [killed_result, unresolved_result],
          duration: 0.6
        )
        output = reporter.call(unresolved_summary)

        expect(output).to include('class="unresolved-details"')
        expect(output).to include("integer_literal")
        expect(output).to include("lib/user.rb")
        expect(output).to include("15")
      end

      it "omits the unresolved section when no unresolved results exist" do
        output = reporter.call(summary)

        expect(output).not_to include('class="unresolved-details"')
      end
    end

    context "with timed out mutations" do
      let(:timeout_mutation) do
        double(
          "Mutation",
          operator_name: "method_call_removal",
          file_path: "lib/user.rb",
          line: 20,
          column: 0,
          diff: "- foo.bar\n+ foo"
        )
      end

      let(:timeout_result) do
        Evilution::Result::MutationResult.new(
          mutation: timeout_mutation,
          status: :timeout,
          duration: 30.0
        )
      end

      it "shows timed out mutations" do
        timeout_summary = Evilution::Result::Summary.new(
          results: [killed_result, timeout_result],
          duration: 30.5
        )
        output = reporter.call(timeout_summary)

        expect(output).to include("timeout")
      end
    end

    context "when truncated" do
      it "shows truncation notice" do
        truncated_summary = Evilution::Result::Summary.new(
          results: [survived_result],
          duration: 0.1,
          truncated: true
        )
        output = reporter.call(truncated_summary)

        expect(output).to include("Truncated")
      end
    end

    it "escapes HTML entities in diffs" do
      html_subj = double("Subject", name: "User#compare")
      html_mutation = double(
        "Mutation",
        operator_name: "comparison_replacement",
        file_path: "lib/user.rb",
        line: 3,
        column: 0,
        diff: "- a < b\n+ a > b",
        subject: html_subj
      )
      html_result = Evilution::Result::MutationResult.new(
        mutation: html_mutation,
        status: :survived,
        duration: 0.1
      )
      html_summary = Evilution::Result::Summary.new(results: [html_result], duration: 0.1)
      output = reporter.call(html_summary)

      expect(output).to include("&lt;")
      expect(output).to include("&gt;")
      expect(output).not_to match(%r{diff.*<[^/!].*>.*</.*>.*[^<]*< b})
    end

    it "includes a per-file mutation map with line indicators" do
      output = reporter.call(summary)

      expect(output).to include("mutation-map")
      expect(output).to include("line 9")
      expect(output).to include("line 5")
    end

    it "includes efficiency metrics" do
      r1 = Evilution::Result::MutationResult.new(mutation: killed_mutation, status: :killed, duration: 3.0)
      r2 = Evilution::Result::MutationResult.new(mutation: survived_mutation, status: :survived, duration: 2.0)
      s = Evilution::Result::Summary.new(results: [r1, r2], duration: 10.0)

      output = reporter.call(s)

      expect(output).to include("Efficiency")
      expect(output).to include("50.0%")
      expect(output).to include("Rate")
      expect(output).to include("0.20/s")
    end

    it "omits efficiency cards when duration is zero" do
      s = Evilution::Result::Summary.new(results: [killed_result], duration: 0.0)

      output = reporter.call(s)

      expect(output).not_to include("Efficiency")
      expect(output).not_to include("Rate")
    end

    it "includes peak memory when available" do
      result_with_memory = Evilution::Result::MutationResult.new(
        mutation: killed_mutation,
        status: :killed,
        duration: 0.5,
        child_rss_kb: 51_200
      )
      mem_summary = Evilution::Result::Summary.new(results: [result_with_memory], duration: 0.5)
      output = reporter.call(mem_summary)

      expect(output).to include("50.0")
    end
  end

  describe "baseline comparison" do
    let(:baseline_data) do
      {
        "summary" => { "score" => 0.7, "total" => 10, "killed" => 7, "survived" => 3 },
        "survived" => [
          { "operator" => "comparison_replacement", "file" => "lib/user.rb",
            "line" => 9, "subject" => "User#check" }
        ]
      }
    end

    let(:reporter_with_baseline) { described_class.new(baseline: baseline_data) }

    it "shows a comparison section with score delta" do
      output = reporter_with_baseline.call(summary)

      expect(output).to include("Baseline Comparison")
      expect(output).to include("70.00%")
    end

    it "marks new survivors as regressions" do
      new_subj = double("Subject", name: "User#new_method")
      new_survived_mutation = double(
        "Mutation",
        operator_name: "boolean_literal_replacement",
        file_path: "lib/user.rb",
        line: 15,
        column: 4,
        diff: "- true\n+ false",
        subject: new_subj
      )
      new_survived_result = Evilution::Result::MutationResult.new(
        mutation: new_survived_mutation,
        status: :survived,
        duration: 0.1
      )
      s = Evilution::Result::Summary.new(
        results: [survived_result, new_survived_result],
        duration: 0.3
      )
      output = reporter_with_baseline.call(s)

      expect(output).to include("NEW REGRESSION")
    end

    it "does not mark pre-existing survivors as regressions" do
      output = reporter_with_baseline.call(summary)

      expect(output).not_to include("NEW REGRESSION")
    end

    it "works without baseline (no comparison section)" do
      output = reporter.call(summary)

      expect(output).not_to include("Baseline Comparison")
    end
  end

  describe "error_message rendering" do
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

    it "includes error_message as title attribute on map entry" do
      output = reporter.call(error_summary)

      expect(output).to include('title="syntax error in mutated source: unexpected token"')
    end

    it "collapses whitespace in multi-line error messages for the title attribute" do
      multiline_result = Evilution::Result::MutationResult.new(
        mutation: killed_mutation,
        status: :error,
        duration: 0.05,
        error_message: "syntax error\n  unexpected token\n  at line 5"
      )
      multiline_summary = Evilution::Result::Summary.new(
        results: [multiline_result],
        duration: 1.0
      )

      output = reporter.call(multiline_summary)

      expect(output).to include('title="syntax error unexpected token at line 5"')
    end

    it "escapes HTML in error messages" do
      dangerous_result = Evilution::Result::MutationResult.new(
        mutation: killed_mutation,
        status: :error,
        duration: 0.05,
        error_message: 'oops <script>alert("x")</script>'
      )
      dangerous_summary = Evilution::Result::Summary.new(
        results: [dangerous_result],
        duration: 1.0
      )

      output = reporter.call(dangerous_summary)

      expect(output).not_to include("<script>alert")
      expect(output).to include("&lt;script&gt;")
    end
  end

  describe "error details section" do
    let(:error_mutation_a) do
      double(
        "Mutation",
        operator_name: "boolean_literal_replacement",
        file_path: "lib/user.rb",
        line: 5,
        column: 8,
        diff: "- true\n+ false"
      )
    end

    let(:error_mutation_b) do
      double(
        "Mutation",
        operator_name: "integer_literal",
        file_path: "lib/user.rb",
        line: 12,
        column: 4,
        diff: "- 1\n+ 0"
      )
    end

    let(:error_result_a) do
      Evilution::Result::MutationResult.new(
        mutation: error_mutation_a,
        status: :error,
        duration: 0.05,
        error_message: "syntax error at line 5"
      )
    end

    let(:error_result_b) do
      Evilution::Result::MutationResult.new(
        mutation: error_mutation_b,
        status: :error,
        duration: 0.05,
        error_message: "NoMethodError: undefined method `foo'"
      )
    end

    let(:error_details_summary) do
      Evilution::Result::Summary.new(
        results: [killed_result, error_result_a, error_result_b],
        duration: 1.0
      )
    end

    it "renders an error details section with count" do
      output = reporter.call(error_details_summary)

      expect(output).to include(%(<div class="error-details">))
      expect(output).to include("Errors (2)")
    end

    it "renders an entry per errored result with operator and location" do
      output = reporter.call(error_details_summary)

      expect(output).to include("error-entry")
      expect(output).to include("boolean_literal_replacement")
      expect(output).to include("integer_literal")
      expect(output).to include("lib/user.rb:5")
      expect(output).to include("lib/user.rb:12")
    end

    it "shows the full error message inline in the details section" do
      output = reporter.call(error_details_summary)

      expect(output).to include("syntax error at line 5")
      expect(output).to include("NoMethodError: undefined method `foo&#39;")
    end

    it "shows the diff for each errored mutation" do
      output = reporter.call(error_details_summary)

      expect(output).to include("true")
      expect(output).to include("false")
    end

    it "omits the error details section when there are no errors" do
      output = reporter.call(summary)

      expect(output).not_to include(%(<div class="error-details">))
      expect(output).not_to match(/Errors \(\d+\)/)
    end

    it "escapes HTML in the inline error message" do
      nasty = Evilution::Result::MutationResult.new(
        mutation: error_mutation_a,
        status: :error,
        duration: 0.05,
        error_message: "<script>alert(1)</script>"
      )
      nasty_summary = Evilution::Result::Summary.new(results: [nasty], duration: 0.1)

      output = reporter.call(nasty_summary)

      expect(output).to include(%(<div class="error-details">))
      expect(output).not_to include("<script>alert(1)")
      expect(output).to include("&lt;script&gt;alert(1)&lt;/script&gt;")
    end

    it "scopes error entries to their file section" do
      other_file_error_mutation = double(
        "Mutation",
        operator_name: "string_literal",
        file_path: "lib/account.rb",
        line: 3,
        column: 0,
        diff: '- "a"\n+ "b"'
      )
      other_file_error = Evilution::Result::MutationResult.new(
        mutation: other_file_error_mutation,
        status: :error,
        duration: 0.05,
        error_message: "error in account"
      )
      multi_summary = Evilution::Result::Summary.new(
        results: [error_result_a, other_file_error],
        duration: 0.2
      )

      output = reporter.call(multi_summary)

      account_section = output[output.index("lib/account.rb")...output.index("lib/user.rb")]
      user_section = output[output.index("lib/user.rb")..]

      expect(account_section).to include("error in account")
      expect(account_section).not_to include("syntax error at line 5")
      expect(user_section).to include("syntax error at line 5")
      expect(user_section).not_to include("error in account")
    end
  end
end
