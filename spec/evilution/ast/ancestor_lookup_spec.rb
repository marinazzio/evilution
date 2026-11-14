# frozen_string_literal: true

require "spec_helper"
require "evilution/ast/ancestor_lookup"

RSpec.describe Evilution::AST::AncestorLookup do
  around do |example|
    Evilution::AST::ParseCache.clear!
    example.run
    Evilution::AST::ParseCache.clear!
  end

  let(:lookup) { described_class.new }
  let(:source) { "class Order\n  validates :rush\nend\n" }
  let(:symbol) { Prism.parse(source).value.statements.body.first.body.body.first.arguments.arguments.first }

  it "lists the ancestors of a node parsed separately from the same source, nearest first" do
    ancestors = lookup.ancestors(symbol, "a.rb", source).to_a

    expect(ancestors.map(&:class)).to eq(
      [Prism::ArgumentsNode, Prism::CallNode, Prism::StatementsNode, Prism::ClassNode, Prism::StatementsNode,
       Prism::ProgramNode]
    )
  end

  it "lists none without a source" do
    expect(lookup.ancestors(symbol, "a.rb", nil).to_a).to eq([])
  end

  it "builds one index for a source asked about again, or a copy of it" do
    allow(Evilution::AST::ParentIndex).to receive(:new).and_call_original

    lookup.ancestors(symbol, "a.rb", source).to_a
    lookup.ancestors(symbol, "a.rb", source).to_a
    lookup.ancestors(symbol, "a.rb", source.dup).to_a

    expect(Evilution::AST::ParentIndex).to have_received(:new).once
  end

  it "builds a new index for another source" do
    other = "validates :rush\n"
    node = Prism.parse(other).value.statements.body.first.arguments.arguments.first

    lookup.ancestors(symbol, "a.rb", source).to_a

    expect(lookup.ancestors(node, "b.rb", other).map(&:class))
      .to eq([Prism::ArgumentsNode, Prism::CallNode, Prism::StatementsNode, Prism::ProgramNode])
  end
end
