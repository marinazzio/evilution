# frozen_string_literal: true

require "evilution/reporter/suggestion/registry"

RSpec.describe Evilution::Reporter::Suggestion::Registry do
  describe "#register_generic + #generic" do
    it "stores and retrieves a generic suggestion by operator name" do
      registry = described_class.new
      registry.register_generic("comparison_replacement", "Add a boundary test")

      expect(registry.generic("comparison_replacement")).to eq("Add a boundary test")
    end

    it "returns nil for an unknown operator" do
      expect(described_class.new.generic("nope")).to be_nil
    end

    it "returns self from register_generic for chaining" do
      registry = described_class.new

      expect(registry.register_generic("op", "text")).to be(registry)
    end
  end

  describe "#register_concrete + #concrete" do
    it "stores and retrieves a concrete block scoped by integration" do
      registry = described_class.new
      block = ->(_mutation) { "RSpec block" }
      registry.register_concrete("comparison_replacement", integration: :rspec, block: block)

      expect(registry.concrete("comparison_replacement", integration: :rspec)).to be(block)
    end

    it "keeps per-integration tables isolated" do
      registry = described_class.new
      rspec_block    = ->(_) { "rspec" }
      minitest_block = ->(_) { "minitest" }
      registry.register_concrete("op", integration: :rspec, block: rspec_block)
      registry.register_concrete("op", integration: :minitest, block: minitest_block)

      expect(registry.concrete("op", integration: :rspec)).to be(rspec_block)
      expect(registry.concrete("op", integration: :minitest)).to be(minitest_block)
    end

    it "returns self from register_concrete for chaining" do
      registry = described_class.new

      expect(registry.register_concrete("op", integration: :rspec, block: ->(_) {})).to be(registry)
    end

    it "returns nil for an unknown operator" do
      expect(described_class.new.concrete("nope", integration: :rspec)).to be_nil
    end

    it "returns nil for an unknown integration" do
      registry = described_class.new
      registry.register_concrete("op", integration: :rspec, block: ->(_) {})

      expect(registry.concrete("op", integration: :cucumber)).to be_nil
    end
  end

  describe "#each_generic_operator" do
    it "yields each registered operator name to the block" do
      registry = described_class.new
      registry.register_generic("a", "alpha")
      registry.register_generic("b", "beta")
      yielded = []
      registry.each_generic_operator { |op| yielded << op }

      expect(yielded).to contain_exactly("a", "b")
    end

    it "returns an enumerator without a block" do
      registry = described_class.new
      registry.register_generic("a", "alpha")
      registry.register_generic("b", "beta")

      expect(registry.each_generic_operator.to_a).to contain_exactly("a", "b")
    end
  end

  describe ".default" do
    before { described_class.reset! }
    after  { described_class.reset! }

    it "memoizes the same instance across calls" do
      expect(described_class.default).to be(described_class.default)
    end

    it "loads templates so generic lookup returns a non-nil string for a known operator" do
      expect(described_class.default.generic("comparison_replacement")).to be_a(String)
    end

    it "populates rspec concrete entries from RSPEC_ENTRIES" do
      require "evilution/reporter/suggestion/templates/rspec"
      registry = described_class.default
      Evilution::Reporter::Suggestion::Templates::Rspec::RSPEC_ENTRIES.each do |op, blk|
        expect(registry.concrete(op, integration: :rspec)).to be(blk)
      end
    end

    it "populates minitest concrete entries from MINITEST_ENTRIES" do
      require "evilution/reporter/suggestion/templates/minitest"
      registry = described_class.default
      Evilution::Reporter::Suggestion::Templates::Minitest::MINITEST_ENTRIES.each do |op, blk|
        expect(registry.concrete(op, integration: :minitest)).to be(blk)
      end
    end

    it "populates generic entries from GENERIC_ENTRIES" do
      require "evilution/reporter/suggestion/templates/generic"
      registry = described_class.default
      Evilution::Reporter::Suggestion::Templates::Generic::GENERIC_ENTRIES.each do |op, text|
        expect(registry.generic(op)).to eq(text)
      end
    end

    it "reset! clears the memoized default" do
      first = described_class.default
      described_class.reset!

      expect(described_class.default).not_to be(first)
    end
  end
end
