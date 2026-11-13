# frozen_string_literal: true

require "evilution/runner/phase_clock"

RSpec.describe Evilution::Runner::PhaseClock do
  subject(:clock) { described_class.new }

  it "returns what the block returns" do
    expect(clock.measure(:planning) { :plan }).to eq(:plan)
  end

  it "records how long the phase took" do
    clock.measure(:baseline) { sleep 0.05 }

    expect(clock.to_h[:baseline]).to be >= 0.05
  end

  it "lists phases in the order they ran" do
    clock.measure(:preload) { nil }
    clock.measure(:canary) { nil }

    expect(clock.to_h.keys).to eq(%i[preload canary])
  end

  it "adds up a phase measured more than once" do
    clock.measure(:execution) { sleep 0.02 }
    clock.measure(:execution) { sleep 0.02 }

    expect(clock.to_h[:execution]).to be >= 0.04
  end

  it "records a phase that raised" do
    expect { clock.measure(:canary) { raise "boom" } }.to raise_error("boom")

    expect(clock.to_h).to have_key(:canary)
  end

  it "hands out a frozen copy" do
    clock.measure(:preload) { nil }

    expect(clock.to_h).to be_frozen
  end
end
