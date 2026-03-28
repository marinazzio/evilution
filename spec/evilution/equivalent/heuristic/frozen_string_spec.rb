# frozen_string_literal: true

RSpec.describe Evilution::Equivalent::Heuristic::FrozenString do
  subject(:heuristic) { described_class.new }

  it "matches string_literal mutation when original has .freeze call" do
    mutation = double("Mutation",
                      operator_name: "string_literal",
                      diff: "- LABEL = \"active\".freeze\n+ LABEL = \"\".freeze")

    expect(heuristic.match?(mutation)).to be true
  end

  it "matches when freeze is on empty string being mutated to non-empty" do
    mutation = double("Mutation",
                      operator_name: "string_literal",
                      diff: "- DEFAULT = \"\".freeze\n+ DEFAULT = \"mutation\".freeze")

    expect(heuristic.match?(mutation)).to be true
  end

  it "matches when freeze appears after the string without dot-chaining" do
    mutation = double("Mutation",
                      operator_name: "string_literal",
                      diff: "- MSG = \"hello\".freeze\n+ MSG = \"\".freeze")

    expect(heuristic.match?(mutation)).to be true
  end

  it "does not match string_literal mutation without .freeze" do
    mutation = double("Mutation",
                      operator_name: "string_literal",
                      diff: "- name = \"active\"\n+ name = \"\"")

    expect(heuristic.match?(mutation)).to be false
  end

  it "does not match non-string_literal operators even with .freeze in diff" do
    mutation = double("Mutation",
                      operator_name: "method_call_removal",
                      diff: "- \"active\".freeze\n+ \"active\"")

    expect(heuristic.match?(mutation)).to be false
  end

  it "does not match nil replacement of frozen string" do
    mutation = double("Mutation",
                      operator_name: "string_literal",
                      diff: "- LABEL = \"active\".freeze\n+ LABEL = nil")

    expect(heuristic.match?(mutation)).to be false
  end
end
