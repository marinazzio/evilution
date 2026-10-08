# frozen_string_literal: true

require "prism"
require "evilution/ast/round_half_mode"

RSpec.describe Evilution::AST::RoundHalfMode do
  def call_node(code)
    Prism.parse(code).value.statements.body.first
  end

  def mode(code)
    node = described_class.of(call_node(code))
    node.slice if node
  end

  describe ".of" do
    it "returns the literal mode of a round call" do
      expect(mode("amount.round(2, half: :even)")).to eq(":even")
      expect(mode("amount.round(half: :up)")).to eq(":up")
      expect(mode("amount.round half: :down")).to eq(":down")
    end

    it "finds the mode among other keywords and through safe navigation" do
      expect(mode("amount.round(2, **opts, half: :even)")).to eq(":even")
      expect(mode("amount&.round(2, half: :even)")).to eq(":even")
      expect(mode("round(half: :even)")).to eq(":even")
    end

    it "accepts the quoted and rocket spellings of the key" do
      expect(mode('amount.round(2, "half": :even)')).to eq(":even")
      expect(mode("amount.round(2, :half => :even)")).to eq(":even")
    end

    it "returns nil for a mode that is not a literal Ruby accepts" do
      ["amount.round(2, half: mode)", "amount.round(2, half: nil)", "amount.round(2, half: :banker)",
       "amount.round(2, half: 'even')", "amount.round(2, half: :\"e\#{v}en\")"].each do |code|
        expect(mode(code)).to be_nil, code
      end
    end

    it "returns nil when round takes no half: keyword" do
      ["amount.round", "amount.round(2)", "amount.round(2, **opts)", "amount.round(2, :even)",
       "amount.round(2, mode: :even)", "amount.round(2, 'half' => :even)", "amount.round({ half: :even })",
       "amount.round(2, key => :even)"].each do |code|
        expect(mode(code)).to be_nil, code
      end
    end

    it "returns nil for another method or another node" do
      expect(mode("amount.floor(2, half: :even)")).to be_nil
      expect(mode("configure(half: :even)")).to be_nil
      expect(described_class.of(call_node("round = 1"))).to be_nil
      expect(described_class.of(nil)).to be_nil
    end
  end

  describe "::MODES" do
    it "lists the modes Ruby accepts" do
      expect(described_class::MODES).to eq(%i[up even down])
    end
  end
end
