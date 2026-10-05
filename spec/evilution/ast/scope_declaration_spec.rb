# frozen_string_literal: true

require "prism"
require "evilution/ast/scope_declaration"

RSpec.describe Evilution::AST::ScopeDeclaration do
  def statement(code)
    Prism.parse(code).value.statements.body.first
  end

  def class_body(code)
    statement(code).body
  end

  describe ".body_of" do
    it "returns the lambda of a `->` body" do
      expect(described_class.body_of(statement("scope :paid, -> { where(paid: true) }"))).to be_a(Prism::LambdaNode)
    end

    it "returns the block of a `lambda` or `proc` body" do
      %w[lambda proc].each do |maker|
        body = described_class.body_of(statement("scope :paid, #{maker} { where(paid: true) }"))

        expect(body).to be_a(Prism::BlockNode)
        expect(body.slice).to eq("{ where(paid: true) }")
      end
    end

    it "returns nil for a body that is not a literal block" do
      [
        "scope :paid, PaidQuery",
        "scope :paid, lambda(&block)",
        "scope :paid, lambda",
        "scope :paid, builder.lambda { all }",
        "scope :paid, build { all }"
      ].each { |code| expect(described_class.body_of(statement(code))).to be_nil, code }
    end

    it "returns nil for calls that are not a scope declaration" do
      [
        "42",
        "where :paid, -> { all }",
        "self.scope :paid, -> { all }",
        "scope",
        "scope :paid",
        "scope 'paid', -> { all }",
        "scope :paid, -> { all }, :extra"
      ].each { |code| expect(described_class.body_of(statement(code))).to be_nil, code }
    end
  end

  describe ".scope_name" do
    it "returns the declared name" do
      expect(described_class.scope_name(statement("scope :for_owner, -> { all }"))).to eq("for_owner")
    end
  end

  describe ".in_body" do
    it "returns the scope declarations among a class body's statements" do
      body = class_body(<<~RUBY)
        class Order
          scope :paid, -> { where(paid: true) }
          include Comparable
          scope :open, lambda { where(open: true) }
        end
      RUBY

      expect(described_class.in_body(body).map { |node| described_class.scope_name(node) }).to eq(%w[paid open])
    end

    it "looks into a body that has a rescue clause" do
      body = class_body(<<~RUBY)
        class Order
          scope :paid, -> { where(paid: true) }
        rescue NameError
          nil
        end
      RUBY

      expect(described_class.in_body(body).length).to eq(1)
    end

    it "returns nothing for an empty body" do
      expect(described_class.in_body(class_body("class Order; end"))).to eq([])
      expect(described_class.in_body(class_body("class Order\nrescue NameError\nend"))).to eq([])
    end
  end
end
