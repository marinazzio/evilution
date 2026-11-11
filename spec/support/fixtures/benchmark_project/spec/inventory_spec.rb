# frozen_string_literal: true

require_relative "spec_helper"
require "inventory"

RSpec.describe Inventory do
  subject(:inventory) { described_class.new }

  before { sleep SLOW_EXAMPLE_SECONDS }

  it "starts empty" do
    expect(inventory.total).to eq(0)
  end

  it "adds one item by default" do
    inventory.add("apple")
    expect(inventory.count("apple")).to eq(1)
  end

  it "accumulates counts" do
    inventory.add("apple", 2)
    inventory.add("apple", 3)
    expect(inventory.count("apple")).to eq(5)
  end

  it "rejects non-positive counts" do
    expect { inventory.add("apple", 0) }.to raise_error(ArgumentError, "count must be positive")
  end

  it "removes items" do
    inventory.add("apple", 3)
    expect(inventory.remove("apple", 2)).to be(true)
    expect(inventory.count("apple")).to eq(1)
  end

  it "drops a name when its count reaches zero" do
    inventory.add("apple", 2)
    inventory.remove("apple", 2)
    expect(inventory.names).to eq([])
  end

  it "refuses to remove more than it has" do
    inventory.add("apple", 1)
    expect(inventory.remove("apple", 2)).to be(false)
    expect(inventory.count("apple")).to eq(1)
  end

  it "removes one item by default" do
    inventory.add("apple", 2)
    inventory.remove("apple")
    expect(inventory.count("apple")).to eq(1)
  end

  it "sums all counts" do
    inventory.add("apple", 2)
    inventory.add("pear", 3)
    expect(inventory.total).to eq(5)
  end

  it "lists low-stock names sorted" do
    inventory.add("pear", 1)
    inventory.add("apple", 2)
    inventory.add("plum", 3)
    expect(inventory.low_stock).to eq(%w[apple pear])
  end

  it "uses a custom low-stock threshold" do
    inventory.add("apple", 3)
    expect(inventory.low_stock(3)).to eq(["apple"])
  end

  it "lists names sorted" do
    inventory.add("pear")
    inventory.add("apple")
    expect(inventory.names).to eq(%w[apple pear])
  end
end
