# frozen_string_literal: true

require "evilution/result/mutation_timings"

RSpec.describe Evilution::Result::MutationTimings do
  describe ".from_h" do
    it "returns nil for nil" do
      expect(described_class.from_h(nil)).to be_nil
    end

    it "returns nil for something that is not a Hash" do
      expect(described_class.from_h(false)).to be_nil
    end

    it "returns nil for a truthy value that is not a Hash" do
      expect(described_class.from_h("apply")).to be_nil
    end

    it "accepts a Hash subclass" do
      expect(described_class.from_h(Class.new(Hash)[:apply, 0.1]).apply).to eq(0.1)
    end

    it "keeps every phase when all four were measured" do
      all = { apply: 0.1, test_run: 0.2, confirmation: 0.3, queue_wait: 0.4 }

      expect(described_class.from_h(all).to_h).to eq(all)
    end

    it "returns nil when no known phase carries a number" do
      expect(described_class.from_h({ other: 1.0, apply: nil })).to be_nil
    end

    it "builds timings from the phases present" do
      timings = described_class.from_h({ apply: 0.1, test_run: 0.5 })

      expect(timings.apply).to eq(0.1)
      expect(timings.test_run).to eq(0.5)
      expect(timings.confirmation).to be_nil
      expect(timings.queue_wait).to be_nil
    end

    it "ignores a phase whose value is not numeric" do
      timings = described_class.from_h({ apply: "0.1", test_run: 0.5 })

      expect(timings.apply).to be_nil
      expect(timings.test_run).to eq(0.5)
    end
  end

  describe "#with_queue_wait" do
    it "returns a copy carrying the queue wait" do
      timings = described_class.new(apply: 0.1, test_run: 0.5)

      waited = timings.with_queue_wait(0.25)

      expect(waited.queue_wait).to eq(0.25)
      expect(waited.apply).to eq(0.1)
      expect(timings.queue_wait).to be_nil
    end
  end

  describe "defaults" do
    it "measures nothing unless told" do
      expect(described_class.new.to_h).to eq({})
    end

    it "keeps the confirmation time it was given" do
      expect(described_class.new(confirmation: 0.3).confirmation).to eq(0.3)
    end

    it "has no setters" do
      expect(described_class.new).not_to respond_to(:apply=)
    end
  end

  it "names the phases in order" do
    expect(described_class::PHASES).to eq(%i[apply test_run confirmation queue_wait])
    expect(described_class::PHASES).to be_frozen
  end

  describe "#to_h" do
    it "lists all four phases when all were measured" do
      all = { apply: 0.1, test_run: 0.2, confirmation: 0.3, queue_wait: 0.4 }

      expect(described_class.new(**all).to_h).to eq(all)
    end

    it "lists only the phases that were measured" do
      timings = described_class.new(apply: 0.1, test_run: 0.5, queue_wait: 0.0)

      expect(timings.to_h).to eq(apply: 0.1, test_run: 0.5, queue_wait: 0.0)
    end
  end

  it "is frozen" do
    expect(described_class.new(apply: 0.1)).to be_frozen
  end
end
