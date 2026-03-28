# frozen_string_literal: true

RSpec.describe Evilution::Equivalent::Heuristic::RedundantBooleanReturn do
  subject(:heuristic) { described_class.new }

  it "matches boolean_literal_replacement replacing true with false in predicate method" do
    node = double("DefNode")
    allow(node).to receive(:is_a?).with(Prism::DefNode).and_return(true)
    allow(node).to receive(:name).and_return(:valid?)

    subject_obj = double("Subject", node: node)
    mutation = double("Mutation",
                      operator_name: "boolean_literal_replacement",
                      subject: subject_obj,
                      diff: "- return true\n+ return false")

    expect(heuristic.match?(mutation)).to be true
  end

  it "matches predicate method ending with question mark returning false to true" do
    node = double("DefNode")
    allow(node).to receive(:is_a?).with(Prism::DefNode).and_return(true)
    allow(node).to receive(:name).and_return(:empty?)

    subject_obj = double("Subject", node: node)
    mutation = double("Mutation",
                      operator_name: "boolean_literal_replacement",
                      subject: subject_obj,
                      diff: "- return false\n+ return true")

    expect(heuristic.match?(mutation)).to be true
  end

  it "does not match boolean replacement in non-predicate method" do
    node = double("DefNode")
    allow(node).to receive(:is_a?).with(Prism::DefNode).and_return(true)
    allow(node).to receive(:name).and_return(:process)

    subject_obj = double("Subject", node: node)
    mutation = double("Mutation",
                      operator_name: "boolean_literal_replacement",
                      subject: subject_obj,
                      diff: "- return true\n+ return false")

    expect(heuristic.match?(mutation)).to be false
  end

  it "does not match boolean to nil replacement even in predicate" do
    node = double("DefNode")
    allow(node).to receive(:is_a?).with(Prism::DefNode).and_return(true)
    allow(node).to receive(:name).and_return(:valid?)

    subject_obj = double("Subject", node: node)
    mutation = double("Mutation",
                      operator_name: "boolean_literal_replacement",
                      subject: subject_obj,
                      diff: "- return true\n+ return nil")

    expect(heuristic.match?(mutation)).to be false
  end

  it "does not match when subject node is not a DefNode" do
    node = double("ClassNode")
    allow(node).to receive(:is_a?).with(Prism::DefNode).and_return(false)

    subject_obj = double("Subject", node: node)
    mutation = double("Mutation",
                      operator_name: "boolean_literal_replacement",
                      subject: subject_obj,
                      diff: "- return true\n+ return false")

    expect(heuristic.match?(mutation)).to be false
  end

  it "does not match when subject node is nil" do
    subject_obj = double("Subject", node: nil)
    mutation = double("Mutation",
                      operator_name: "boolean_literal_replacement",
                      subject: subject_obj,
                      diff: "- return true\n+ return false")

    expect(heuristic.match?(mutation)).to be false
  end

  it "does not match other operators" do
    mutation = double("Mutation",
                      operator_name: "comparison_replacement",
                      diff: "- x >= 10\n+ x > 10")

    expect(heuristic.match?(mutation)).to be false
  end
end
