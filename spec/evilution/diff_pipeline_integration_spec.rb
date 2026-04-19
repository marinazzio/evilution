# frozen_string_literal: true

require "json"
require "evilution/mutation"
require "evilution/result/mutation_result"
require "evilution/result/summary"
require "evilution/reporter/cli"
require "evilution/reporter/json"

RSpec.describe "Survived mutant unified diff (integration)" do
  let(:subject_double) { double("Subject", name: "User#adult?") }

  let(:survived_mutation) do
    Evilution::Mutation.new(
      subject: subject_double,
      operator_name: "comparison_replacement",
      original_source: "def adult?\n  @age >= 18\nend\n",
      mutated_source: "def adult?\n  @age > 18\nend\n",
      original_slice: "  @age >= 18\n",
      mutated_slice: "  @age > 18\n",
      file_path: "lib/user.rb",
      line: 2,
      column: 7
    )
  end

  let(:survived_result) do
    Evilution::Result::MutationResult.new(
      mutation: survived_mutation,
      status: :survived,
      duration: 0.1,
      test_command: "rspec spec/user_spec.rb"
    )
  end

  let(:summary) do
    Evilution::Result::Summary.new(results: [survived_result], duration: 0.5)
  end

  let(:expected_unified_diff) do
    [
      "--- a/lib/user.rb",
      "+++ b/lib/user.rb",
      "@@ -2,1 +2,1 @@",
      "-  @age >= 18",
      "+  @age > 18"
    ].join("\n")
  end

  it "Mutation#unified_diff produces git-style hunk for the survived mutant" do
    expect(survived_mutation.unified_diff).to eq(expected_unified_diff)
  end

  it "CLI reporter renders the unified diff under the survived coverage gap" do
    output = Evilution::Reporter::CLI.new.call(summary)

    expect(output).to include("Survived mutations (1 coverage gap)")
    expect(output).to include("    --- a/lib/user.rb")
    expect(output).to include("    +++ b/lib/user.rb")
    expect(output).to include("    @@ -2,1 +2,1 @@")
    expect(output).to include("    -  @age >= 18")
    expect(output).to include("    +  @age > 18")
  end

  it "JSON reporter exposes unified_diff on the survived entry" do
    payload = JSON.parse(Evilution::Reporter::JSON.new.call(summary))

    expect(payload["survived"].length).to eq(1)
    expect(payload["survived"].first["unified_diff"]).to eq(expected_unified_diff)
  end

  it "JSON reporter exposes unified_diff inside coverage_gaps mutations" do
    payload = JSON.parse(Evilution::Reporter::JSON.new.call(summary))

    expect(payload["coverage_gaps"].length).to eq(1)
    gap_mutation = payload["coverage_gaps"].first["mutations"].first
    expect(gap_mutation["unified_diff"]).to eq(expected_unified_diff)
  end

  context "when slices are unavailable (legacy mutations)" do
    let(:survived_mutation) do
      Evilution::Mutation.new(
        subject: subject_double,
        operator_name: "comparison_replacement",
        original_source: "def adult?\n  @age >= 18\nend\n",
        mutated_source: "def adult?\n  @age > 18\nend\n",
        file_path: "lib/user.rb",
        line: 2
      )
    end

    it "Mutation#unified_diff returns nil" do
      expect(survived_mutation.unified_diff).to be_nil
    end

    it "JSON reporter omits unified_diff key" do
      payload = JSON.parse(Evilution::Reporter::JSON.new.call(summary))

      expect(payload["survived"].first).not_to have_key("unified_diff")
    end

    it "CLI reporter falls back to the line-prefixed diff" do
      output = Evilution::Reporter::CLI.new.call(summary)

      expect(output).to include("Survived mutations (1 coverage gap)")
      expect(output).to include("-   @age >= 18")
      expect(output).to include("+   @age > 18")
      expect(output).not_to include("--- a/lib/user.rb")
    end
  end
end
