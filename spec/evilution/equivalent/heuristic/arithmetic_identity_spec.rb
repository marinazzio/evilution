# frozen_string_literal: true

RSpec.describe Evilution::Equivalent::Heuristic::ArithmeticIdentity do
  subject(:heuristic) { described_class.new }

  it "matches integer_literal replacing 0 with 1 in addition context" do
    mutation = double("Mutation",
                      operator_name: "integer_literal",
                      diff: "- x + 0\n+ x + 1")

    expect(heuristic.match?(mutation)).to be true
  end

  it "matches integer_literal replacing 0 with 1 in subtraction context" do
    mutation = double("Mutation",
                      operator_name: "integer_literal",
                      diff: "- x - 0\n+ x - 1")

    expect(heuristic.match?(mutation)).to be true
  end

  it "matches integer_literal replacing 1 with 0 in multiplication context" do
    mutation = double("Mutation",
                      operator_name: "integer_literal",
                      diff: "- x * 1\n+ x * 0")

    expect(heuristic.match?(mutation)).to be true
  end

  it "matches integer_literal replacing 1 with 0 in division context" do
    mutation = double("Mutation",
                      operator_name: "integer_literal",
                      diff: "- x / 1\n+ x / 0")

    expect(heuristic.match?(mutation)).to be true
  end

  it "matches integer_literal replacing 1 with 0 in exponentiation context" do
    mutation = double("Mutation",
                      operator_name: "integer_literal",
                      diff: "- x ** 1\n+ x ** 0")

    expect(heuristic.match?(mutation)).to be true
  end

  it "does not match integer_literal mutation outside identity context" do
    mutation = double("Mutation",
                      operator_name: "integer_literal",
                      diff: "- x + 5\n+ x + 0")

    expect(heuristic.match?(mutation)).to be false
  end

  it "matches when 0 is the left operand of addition" do
    mutation = double("Mutation",
                      operator_name: "integer_literal",
                      diff: "- 0 + x\n+ 1 + x")

    expect(heuristic.match?(mutation)).to be true
  end

  it "matches when 1 is the left operand of multiplication" do
    mutation = double("Mutation",
                      operator_name: "integer_literal",
                      diff: "- 1 * x\n+ 0 * x")

    expect(heuristic.match?(mutation)).to be true
  end

  it "does not match non-integer operators" do
    mutation = double("Mutation",
                      operator_name: "arithmetic_replacement",
                      diff: "- x + 0\n+ x - 0")

    expect(heuristic.match?(mutation)).to be false
  end

  it "does not match when integer is not an identity element for the operator" do
    mutation = double("Mutation",
                      operator_name: "integer_literal",
                      diff: "- x + 1\n+ x + 0")

    expect(heuristic.match?(mutation)).to be false
  end

  it "does not match standalone integer replacement without arithmetic context" do
    mutation = double("Mutation",
                      operator_name: "integer_literal",
                      diff: "- count = 0\n+ count = 1")

    expect(heuristic.match?(mutation)).to be false
  end
end
