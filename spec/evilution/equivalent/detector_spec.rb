# frozen_string_literal: true

RSpec.describe Evilution::Equivalent::Detector do
  subject(:detector) { described_class.new }

  it "separates equivalent mutations from remaining" do
    noop = double("Mutation", original_source: "x", mutated_source: "x",
                              operator_name: "noop", diff: "", subject: nil, line: 1)
    real = double("Mutation", original_source: "x + 1", mutated_source: "x - 1",
                              operator_name: "arithmetic_replacement", diff: "- x + 1\n+ x - 1",
                              subject: nil, line: 1)

    equivalent, remaining = detector.call([noop, real])

    expect(equivalent).to eq([noop])
    expect(remaining).to eq([real])
  end

  it "returns empty equivalent list when no mutations are equivalent" do
    real = double("Mutation", original_source: "x + 1", mutated_source: "x - 1",
                              operator_name: "arithmetic_replacement", diff: "- x + 1\n+ x - 1",
                              subject: nil, line: 1)

    equivalent, remaining = detector.call([real])

    expect(equivalent).to be_empty
    expect(remaining).to eq([real])
  end

  it "handles empty input" do
    equivalent, remaining = detector.call([])

    expect(equivalent).to be_empty
    expect(remaining).to be_empty
  end

  it "accepts custom heuristics" do
    always_match = double("Heuristic", match?: true)
    detector = described_class.new(heuristics: [always_match])
    mutation = double("Mutation")

    equivalent, remaining = detector.call([mutation])

    expect(equivalent).to eq([mutation])
    expect(remaining).to be_empty
  end
end
