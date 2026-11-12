# frozen_string_literal: true

require "evilution/ast/parse_cache"

RSpec.describe Evilution::AST::ParseCache do
  around do |example|
    described_class.clear!
    example.run
    described_class.clear!
  end

  describe ".tree_for" do
    it "returns the parsed program" do
      expect(described_class.tree_for("a.rb", "x = 1\n")).to be_a(Prism::ProgramNode)
    end

    it "returns the same tree for an unchanged source" do
      first = described_class.tree_for("a.rb", "x = 1\n")

      expect(described_class.tree_for("a.rb", +"x = 1\n")).to equal(first)
    end

    it "parses again when the source of a path changes" do
      first = described_class.tree_for("a.rb", "x = 1\n")
      second = described_class.tree_for("a.rb", "y = 2\n")

      expect(second).not_to equal(first)
      expect(second.statements.body.first.name).to eq(:y)
    end

    it "keeps one tree per path" do
      first = described_class.tree_for("a.rb", "x = 1\n")
      described_class.tree_for("b.rb", "x = 1\n")

      expect(described_class.tree_for("a.rb", "x = 1\n")).to equal(first)
    end
  end

  describe ".clear!" do
    it "makes the next lookup parse anew" do
      first = described_class.tree_for("a.rb", "x = 1\n")
      described_class.clear!

      expect(described_class.tree_for("a.rb", "x = 1\n")).not_to equal(first)
    end
  end
end
