# frozen_string_literal: true

require "prism"
require "evilution/ast/value_object_definition"

RSpec.describe Evilution::AST::ValueObjectDefinition do
  def call_node(code)
    Prism.parse(code).value.statements.body.first
  end

  describe ".match?" do
    it "accepts Data.define and Struct.new" do
      expect(described_class.match?(call_node("Data.define(:x, :y)"))).to be true
      expect(described_class.match?(call_node("Struct.new(:a, :b)"))).to be true
      expect(described_class.match?(call_node("Struct.new(:a) do\nend"))).to be true
    end

    it "accepts a top-level constant path receiver" do
      expect(described_class.match?(call_node("::Data.define(:x)"))).to be true
      expect(described_class.match?(call_node("::Struct.new(:x)"))).to be true
    end

    it "rejects other receivers and other methods" do
      expect(described_class.match?(call_node("Data.new(:x)"))).to be false
      expect(described_class.match?(call_node("Struct.define(:x)"))).to be false
      expect(described_class.match?(call_node("Foo::Data.define(:x)"))).to be false
      expect(described_class.match?(call_node("data.define(:x)"))).to be false
      expect(described_class.match?(call_node("define(:x)"))).to be false
      expect(described_class.match?(call_node("Set.new(:x)"))).to be false
    end

    it "rejects nodes that are not calls" do
      expect(described_class.match?(call_node("Data"))).to be false
      expect(described_class.match?(nil)).to be false
    end
  end
end
