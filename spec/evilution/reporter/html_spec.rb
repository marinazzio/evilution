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

      expect(output).to include("comparison_replacement")
      expect(output).to include("lib/user.rb")
      expect(output).to include("x &gt;= 10")
      expect(output).to include("x &gt; 10")
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
      html_mutation = double(
        "Mutation",
        operator_name: "comparison_replacement",
        file_path: "lib/user.rb",
        line: 3,
        column: 0,
        diff: "- a < b\n+ a > b"
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
end
