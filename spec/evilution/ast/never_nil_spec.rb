# frozen_string_literal: true

require "prism"
require "evilution/ast/never_nil"

RSpec.describe Evilution::AST::NeverNil do
  def node(code)
    Prism.parse(code).value.statements.body.first
  end

  describe ".node?" do
    it "is true for self" do
      expect(described_class.node?(node("self"))).to be(true)
    end

    it "is true for a literal" do
      literals = ["\"a\"", "\"a\#{b}\"", "`ls`", ":a", ":\"a\#{b}\"", "1", "1.5", "3r", "2i", "[a]", "{ a: 1 }", "1..2", "/a/",
                  "/a\#{b}/", "true", "false", "-> { a }"]

      expect(literals.map { |code| described_class.node?(node(code)) }).to all(be(true))
    end

    it "is false for nil itself" do
      expect(described_class.node?(node("nil"))).to be(false)
    end

    it "is false for anything read or computed" do
      values = ["a", "@a", "@@a", "$a", "A", "A::B", "a.b", "a + 1", "(1..2)", "a ? 1 : 2"]

      expect(values.map { |code| described_class.node?(node(code)) }).to all(be(false))
    end
  end
end
