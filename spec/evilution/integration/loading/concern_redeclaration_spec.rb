# frozen_string_literal: true

require "evilution/integration/loading/concern_redeclaration"

RSpec.describe Evilution::Integration::Loading::ConcernRedeclaration do
  # A concern, as far as this module cares: something classes include that
  # holds the block its `included` call registered.
  def concern_with(&block)
    Module.new.tap { |mod| mod.instance_variable_set(:@_included_block, block) if block }
  end

  describe ".skipping?" do
    it "is false outside a redeclaration" do
      expect(described_class.skipping?).to be(false)
    end
  end

  describe ".call" do
    it "runs the registered block on each class that includes the concern" do
      concern = concern_with { define_singleton_method(:marked) { :yes } }
      first = Class.new { include concern }
      second = Class.new { include concern }

      described_class.call(concern)

      expect([first.marked, second.marked]).to eq(%i[yes yes])
    end

    it "runs the block as the class, like the include did" do
      seen = []
      concern = concern_with { seen << self }
      includer = Class.new { include concern }

      described_class.call(concern)

      expect(seen).to eq([includer])
    end

    it "reports skipping while the block runs, and not afterwards" do
      observed = []
      concern = concern_with { observed << Evilution::Integration::Loading::ConcernRedeclaration.skipping? }
      Class.new { include concern }

      described_class.call(concern)

      expect(observed).to eq([true])
      expect(described_class.skipping?).to be(false)
    end

    it "stops skipping when the block raises" do
      concern = concern_with { raise ArgumentError, "bad scope" }
      Class.new { include concern }

      expect { described_class.call(concern) }.to raise_error(ArgumentError, "bad scope")
      expect(described_class.skipping?).to be(false)
    end

    it "leaves a subclass to inherit from the class that includes the concern" do
      seen = []
      concern = concern_with { seen << self }
      parent = Class.new { include concern }
      Class.new(parent)

      described_class.call(concern)

      expect(seen).to eq([parent])
    end

    it "leaves classes that do not include the concern alone" do
      seen = []
      concern = concern_with { seen << self }
      Class.new

      described_class.call(concern)

      expect(seen).to eq([])
    end

    it "does not trust a class's own include? or superclass" do
      seen = []
      concern = concern_with { seen << self }
      odd = Class.new do
        include concern

        def self.include?(*) = raise("not a module question")
        def self.superclass = raise("not asked")
      end

      described_class.call(concern)

      expect(seen).to eq([odd])
    end

    it "does nothing for a concern with no registered block" do
      concern = concern_with
      Class.new { include concern }

      expect { described_class.call(concern) }.not_to raise_error
    end
  end
end
