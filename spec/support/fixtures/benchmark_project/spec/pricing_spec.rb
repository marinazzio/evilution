# frozen_string_literal: true

require_relative "spec_helper"
require "pricing"

RSpec.describe Pricing do
  subject(:pricing) { described_class.new(5) }

  before { sleep SLOW_EXAMPLE_SECONDS }

  describe "#subtotal" do
    it { expect(pricing.subtotal(0)).to eq(0) }
    it { expect(pricing.subtotal(-1)).to eq(0) }
    it { expect(pricing.subtotal(1)).to eq(5) }
    it { expect(pricing.subtotal(9)).to eq(45) }
    it { expect(pricing.subtotal(10)).to eq(45.0) }
    it { expect(pricing.subtotal(20)).to eq(90.0) }
  end

  describe "#with_tax" do
    it { expect(pricing.with_tax(1)).to eq(6.0) }
    it { expect(pricing.with_tax(10)).to eq(54.0) }
    it { expect(pricing.with_tax(0)).to eq(0.0) }
  end

  describe "#discount_label" do
    it { expect(pricing.discount_label(1)).to eq("retail") }
    it { expect(pricing.discount_label(9)).to eq("retail") }
    it { expect(pricing.discount_label(10)).to eq("bulk") }
    it { expect(pricing.discount_label(49)).to eq("bulk") }
    it { expect(pricing.discount_label(50)).to eq("wholesale") }
  end
end
