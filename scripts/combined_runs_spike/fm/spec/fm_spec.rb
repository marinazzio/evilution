# frozen_string_literal: true

require_relative "spec_helper"

RSpec.describe Fm do # rubocop:disable Metrics/BlockLength -- one describe per subject, as measured
  describe Fm::Writer do
    it "exposes the entry inside the block" do
      Fm::Writer.new.with_entry(:k, 1) { expect(Fm::STORE[:k]).to eq(1) }
    end
  end

  describe Fm::Reader do
    it "reports a missing key" do
      expect(Fm::Reader.new.read(:k)).to eq(:missing)
    end
  end

  describe Fm::Router do
    it "routes a positive number" do
      expect(Fm::Router.new.route(5)).to eq(:positive)
    end
  end

  describe Fm::Helper do
    it "labels a positive number" do
      expect(Fm::Helper.new.label(3)).to eq(:positive)
    end

    it "labels a negative number" do
      expect(Fm::Helper.new.label(-3)).to eq(:other)
    end
  end

  describe Fm::Looper do
    it "counts up" do
      expect(Fm::Looper.new.count(3)).to eq(3)
    end
  end
end
