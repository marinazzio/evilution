# frozen_string_literal: true

require "evilution/class_tree"

RSpec.describe Evilution::ClassTree do
  let(:root) { Class.new }

  describe ".descendants" do
    it "lists every class below the root, however deep" do
      child = Class.new(root)
      grandchild = Class.new(child)
      sibling = Class.new(root)

      expect(described_class.descendants(root)).to contain_exactly(child, grandchild, sibling)
    end

    it "leaves the root out" do
      expect(described_class.descendants(root)).to eq([])
    end

    it "leaves out classes outside the root's tree" do
      Class.new

      expect(described_class.descendants(root)).to eq([])
    end

    it "leaves out singleton classes" do
      child = Class.new(root)
      child.singleton_class

      expect(described_class.descendants(root)).to eq([child])
    end

    # Reaching the classes from the root, rather than walking ObjectSpace, is
    # the point: a walk touches every object on the heap.
    it "does not walk the heap" do
      Class.new(root)
      allow(ObjectSpace).to receive(:each_object).and_call_original

      described_class.descendants(root)

      expect(ObjectSpace).not_to have_received(:each_object)
    end

    it "does not trust a class's own subclasses" do
      odd = Class.new(root) { def self.subclasses = raise("not asked") }
      below = Class.new(odd)

      expect(described_class.descendants(root)).to contain_exactly(odd, below)
    end
  end

  describe ".visit" do
    it "yields the root first and a parent before its children" do
      child = Class.new(root)
      grandchild = Class.new(child)
      seen = []

      described_class.visit(root) { |klass| seen << klass }

      expect(seen).to eq([root, child, grandchild])
    end

    it "does not descend below a class the block answers falsy for" do
      child = Class.new(root)
      Class.new(child)
      seen = []

      described_class.visit(root) { |klass| (seen << klass) && klass == root }

      expect(seen).to eq([root, child])
    end
  end
end
