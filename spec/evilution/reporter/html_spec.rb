# frozen_string_literal: true

require "evilution/reporter/html"
require "evilution/result/mutation_result"
require "evilution/result/summary"

RSpec.describe Evilution::Reporter::HTML do
  subject(:reporter) { described_class.new }

  let(:survived_mutation) do
    double(
      "Mutation",
      operator_name: "comparison_replacement",
      file_path: "lib/user.rb",
      line: 9,
      column: 4,
      diff: "- x >= 10\n+ x > 10"
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

      expect(output).to include("2")    # total
      expect(output).to include("1")    # killed
      expect(output).to include("50.00%") # score
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
      expect(output).to include("0")
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
end
