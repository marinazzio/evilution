# frozen_string_literal: true

require "prism"
require "evilution/ast/included_block"

RSpec.describe Evilution::AST::IncludedBlock do
  def statement(code)
    Prism.parse(code).value.statements.body.first
  end

  def module_body(code)
    statement(code).body
  end

  describe ".of" do
    it "returns the block of an `included do ... end` call" do
      block = described_class.of(statement("included do\n  scope :a, -> { 1 }\nend"))

      expect(block).to be_a(Prism::BlockNode)
    end

    it "returns the block of a brace form" do
      expect(described_class.of(statement("included { scope :a, -> { 1 } }"))).to be_a(Prism::BlockNode)
    end

    it "returns nil for anything else" do
      ["included", "included(base)", "included(base) { 1 }", "self.included { 1 }", "Concern.included { 1 }",
       "included(&blk)", "prepended do\nend", "def self.included(base); end", "x = 1"].each do |code|
        expect(described_class.of(statement(code))).to be_nil
      end
    end
  end

  describe ".in_body" do
    it "finds the included blocks among a module body's direct statements" do
      body = module_body("module P\n  extend ActiveSupport::Concern\n  included do\n    a\n  end\n  def x; end\nend")

      expect(described_class.in_body(body).map(&:slice)).to eq(["do\n    a\n  end"])
    end

    it "ignores an included block nested in another statement" do
      body = module_body("module P\n  if rails?\n    included do\n      a\n    end\n  end\nend")

      expect(described_class.in_body(body)).to eq([])
    end

    it "returns nothing for an empty body" do
      expect(described_class.in_body(module_body("module P\nend"))).to eq([])
    end
  end
end
