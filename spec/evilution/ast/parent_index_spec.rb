# frozen_string_literal: true

require "prism"
require "evilution/ast/parent_index"

RSpec.describe Evilution::AST::ParentIndex do
  let(:source) { "class Order\n  validates :rush, if: :paid\nend\n" }
  let(:tree) { Prism.parse(source).value }
  let(:index) { described_class.new(tree) }

  def validates_call(root)
    root.statements.body.first.body.body.first
  end

  def ancestor_types(node)
    index.enum_for(:each_ancestor, node).map(&:type)
  end

  describe "#each_ancestor" do
    it "yields the ancestors of a node, nearest first, up to the root" do
      symbol = validates_call(tree).arguments.arguments.first

      expect(ancestor_types(symbol)).to eq(%i[arguments_node call_node statements_node class_node statements_node program_node])
    end

    it "yields the ancestors of a node from another parse of the same source" do
      other_parse = Prism.parse(source).value
      symbol = validates_call(other_parse).arguments.arguments.first

      expect(index.enum_for(:each_ancestor, symbol).first).to equal(validates_call(tree).arguments)
    end

    it "yields nothing for the root" do
      expect(ancestor_types(tree)).to eq([])
    end

    it "yields nothing for a node the tree does not hold" do
      stranger = Prism.parse("x = 1").value.statements.body.first

      expect(ancestor_types(stranger)).to eq([])
    end

    it "tells apart nodes of one type and length at different offsets" do
      two_calls = Prism.parse("foo(:a)\nbar(:b)\n").value
      two_index = described_class.new(two_calls)
      callers = two_calls.statements.body.map do |call|
        two_index.enum_for(:each_ancestor, call.arguments.arguments.first).to_a[1].name
      end

      expect(callers).to eq(%i[foo bar])
    end

    it "tells apart nodes of one type at one offset over different lengths" do
      chain = Prism.parse("a.b.c\n").value
      outer = chain.statements.body.first

      expect(described_class.new(chain).enum_for(:each_ancestor, outer.receiver.receiver).map(&:type))
        .to eq(%i[call_node call_node statements_node program_node])
    end

    it "keeps how it walks the tree to itself" do
      expect(index.private_methods(false)).to include(:record, :key)
    end

    it "tells apart nodes of different types over the same bytes" do
      statements = tree.statements.body.first.body
      call = validates_call(tree)

      expect(statements.location.start_offset).to eq(call.location.start_offset)
      expect(statements.location.length).to eq(call.location.length)
      expect(index.enum_for(:each_ancestor, call).first).to equal(statements)
      expect(index.enum_for(:each_ancestor, statements).first.type).to eq(:class_node)
    end
  end
end
