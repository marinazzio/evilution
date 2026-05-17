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

  it "matches count -> size swap" do
    mutation = double("Mutation",
                      operator_name: "send_mutation",
                      diff: "- items.count\n+ items.size")

    expect(heuristic.match?(mutation)).to be true
  end

  it "matches size -> count swap" do
    mutation = double("Mutation",
                      operator_name: "send_mutation",
                      diff: "- items.size\n+ items.count")

    expect(heuristic.match?(mutation)).to be true
  end

  it "does not match non-alias send mutations" do
    mutation = double("Mutation",
                      operator_name: "send_mutation",
                      diff: "- obj.public_send(:foo)\n+ obj.send(:foo)")

    expect(heuristic.match?(mutation)).to be false
  end

  it "matches count -> length swap from collection_replacement" do
    mutation = double("Mutation",
                      operator_name: "collection_replacement",
                      diff: "- items.count\n+ items.length")

    expect(heuristic.match?(mutation)).to be true
  end

  it "matches length -> count swap from collection_replacement" do
    mutation = double("Mutation",
                      operator_name: "collection_replacement",
                      diff: "- items.length\n+ items.count")

    expect(heuristic.match?(mutation)).to be true
  end

  it "matches detect -> find from collection_replacement" do
    mutation = double("Mutation",
                      operator_name: "collection_replacement",
                      diff: "- list.detect { |x| x > 0 }\n+ list.find { |x| x > 0 }")

    expect(heuristic.match?(mutation)).to be true
  end

  it "does not match select -> reject from collection_replacement" do
    mutation = double("Mutation",
                      operator_name: "collection_replacement",
                      diff: "- items.select { |x| x > 0 }\n+ items.reject { |x| x > 0 }")

    expect(heuristic.match?(mutation)).to be false
  end

  it "does not match other operators" do
    mutation = double("Mutation",
                      operator_name: "comparison_replacement",
                      diff: "- x >= 10\n+ x > 10")

    expect(heuristic.match?(mutation)).to be false
  end

  it "does not match an alias-pair diff carried by a non-matching operator" do
    # The diff is a genuine detect -> find alias swap, but the operator is not
    # in MATCHING_OPERATORS. The operator guard must reject it regardless.
    mutation = double("Mutation",
                      operator_name: "arithmetic_replacement",
                      diff: "- [1, 2].detect { |x| x > 1 }\n+ [1, 2].find { |x| x > 1 }")

    expect(heuristic.match?(mutation)).to be false
  end

  it "does not match when the removed line has no extractable method" do
    # The "- " line is bare (no .method call), so extract_method returns nil.
    # The removed && added guard must reject before calling to_sym on nil.
    mutation = double("Mutation",
                      operator_name: "send_mutation",
                      diff: "- x + 1\n+ arr.size")

    expect(heuristic.match?(mutation)).to be false
  end

  it "does not match when the diff has no removed line at all" do
    # No line begins with "- ", so extract_method finds no line.
    # The "return nil unless line" guard must prevent matching against nil.
    mutation = double("Mutation",
                      operator_name: "send_mutation",
                      diff: "+ arr.size")

    expect(heuristic.match?(mutation)).to be false
  end
end
