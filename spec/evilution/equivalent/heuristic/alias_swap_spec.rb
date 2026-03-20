# frozen_string_literal: true

RSpec.describe Evilution::Equivalent::Heuristic::AliasSwap do
  subject(:heuristic) { described_class.new }

  it "matches detect -> find swap" do
    mutation = double("Mutation",
                      operator_name: "send_mutation",
                      diff: "- [1, 2].detect { |x| x > 1 }\n+ [1, 2].find { |x| x > 1 }")

    expect(heuristic.match?(mutation)).to be true
  end

  it "matches find -> detect swap" do
    mutation = double("Mutation",
                      operator_name: "send_mutation",
                      diff: "- [1, 2].find { |x| x > 1 }\n+ [1, 2].detect { |x| x > 1 }")

    expect(heuristic.match?(mutation)).to be true
  end

  it "matches length -> size swap" do
    mutation = double("Mutation",
                      operator_name: "send_mutation",
                      diff: "- arr.length\n+ arr.size")

    expect(heuristic.match?(mutation)).to be true
  end

  it "matches size -> length swap" do
    mutation = double("Mutation",
                      operator_name: "send_mutation",
                      diff: "- arr.size\n+ arr.length")

    expect(heuristic.match?(mutation)).to be true
  end

  it "matches collect -> map swap" do
    mutation = double("Mutation",
                      operator_name: "send_mutation",
                      diff: "- arr.collect { |x| x }\n+ arr.map { |x| x }")

    expect(heuristic.match?(mutation)).to be true
  end

  it "does not match flat_map -> map swap" do
    mutation = double("Mutation",
                      operator_name: "send_mutation",
                      diff: "- arr.flat_map { |x| [x] }\n+ arr.map { |x| [x] }")

    expect(heuristic.match?(mutation)).to be false
  end

  it "does not match non-alias send mutations" do
    mutation = double("Mutation",
                      operator_name: "send_mutation",
                      diff: "- obj.public_send(:foo)\n+ obj.send(:foo)")

    expect(heuristic.match?(mutation)).to be false
  end

  it "does not match other operators" do
    mutation = double("Mutation",
                      operator_name: "comparison_replacement",
                      diff: "- x >= 10\n+ x > 10")

    expect(heuristic.match?(mutation)).to be false
  end
end
