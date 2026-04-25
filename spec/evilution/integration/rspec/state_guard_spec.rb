# frozen_string_literal: true

require "spec_helper"
require "evilution/integration/rspec/state_guard"

RSpec.describe Evilution::Integration::RSpec::StateGuard do
  let(:fake_strategy_class) do
    Class.new do
      attr_reader :snapshots, :releases

      def initialize(label)
        @label = label
        @snapshots = 0
        @releases = []
      end

      def snapshot
        @snapshots += 1
        "#{@label}_token"
      end

      def release(token)
        @releases << token
      end
    end
  end

  it "snapshot calls each strategy in order, returning [strategy, token] pairs" do
    a = fake_strategy_class.new("a")
    b = fake_strategy_class.new("b")
    guard = described_class.new(strategies: [a, b])

    token = guard.snapshot

    expect(token).to eq([[a, "a_token"], [b, "b_token"]])
    expect(a.snapshots).to eq(1)
    expect(b.snapshots).to eq(1)
  end

  it "release fans out in REVERSE order" do
    order = []
    a = fake_strategy_class.new("a").tap do |s|
      s.define_singleton_method(:release) { |t| order << "a:#{t}" }
    end
    b = fake_strategy_class.new("b").tap do |s|
      s.define_singleton_method(:release) { |t| order << "b:#{t}" }
    end
    guard = described_class.new(strategies: [a, b])

    token = guard.snapshot
    guard.release(token)

    expect(order).to eq(["b:b_token", "a:a_token"])
  end

  it "release continues if one strategy raises" do
    raising = fake_strategy_class.new("r").tap do |s|
      s.define_singleton_method(:release) { |_| raise StandardError, "boom" }
    end
    succeeding = fake_strategy_class.new("s")
    guard = described_class.new(strategies: [raising, succeeding])

    token = guard.snapshot
    expect { guard.release(token) }.to output(/state release failed for/).to_stderr
    expect(succeeding.releases).to eq(["s_token"])
  end

  it "uses DEFAULT_STRATEGIES when none provided (smoke test)" do
    expect { described_class.new }.not_to raise_error
    expect(described_class::DEFAULT_STRATEGIES).to all(respond_to(:snapshot, :release))
  end
end
