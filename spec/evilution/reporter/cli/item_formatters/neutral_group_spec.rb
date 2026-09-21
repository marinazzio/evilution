# frozen_string_literal: true

RSpec.describe Evilution::Reporter::CLI::ItemFormatters::NeutralGroup do
  subject(:formatter) { described_class.new }

  def result(reason, operator:, line:)
    mutation = instance_double(Evilution::Mutation, operator_name: operator, file_path: "lib/tally.rb", line: line)
    Evilution::Result::MutationResult.new(
      mutation: mutation, status: :neutral, duration: 0.01, neutral_reason: reason
    )
  end

  let(:baseline) { Evilution::Result::NeutralReason.baseline_failure("spec/tally_spec.rb") }

  describe "#format" do
    it "puts the reason above the mutations it explains" do
      group = [baseline, [result(baseline, operator: "arithmetic_replacement", line: 9),
                          result(baseline, operator: "integer_literal", line: 9)]]

      expect(formatter.format(group)).to eq(
        "  baseline already failing (spec/tally_spec.rb):\n    " \
        "arithmetic_replacement: lib/tally.rb:9\n    " \
        "integer_literal: lib/tally.rb:9"
      )
    end

    it "names an infrastructure error by its class" do
      reason = Evilution::Result::NeutralReason.infra_error("Timeout::Error")
      group = [reason, [result(reason, operator: "method_call_removal", line: 3)]]

      expect(formatter.format(group)).to eq(
        "  infrastructure error (Timeout::Error):\n    method_call_removal: lib/tally.rb:3"
      )
    end

    # Results recorded before the reason existed, or restored from an older
    # saved session, still have to render.
    it "falls back to a plain heading when the reason is unknown" do
      group = [nil, [result(nil, operator: "block_removal", line: 4)]]

      expect(formatter.format(group)).to eq(
        "  reason not recorded:\n    block_removal: lib/tally.rb:4"
      )
    end
  end
end
