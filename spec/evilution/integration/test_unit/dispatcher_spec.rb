# frozen_string_literal: true

require "evilution/integration/test_unit"
require "evilution/integration/test_unit/framework_loader"
require "evilution/integration/test_unit/dispatcher"

RSpec.describe Evilution::Integration::TestUnit::Dispatcher do
  before(:context) do
    Evilution::Integration::TestUnit::FrameworkLoader.new.call
    runs = -> { Thread.current[:evilution_dispatcher_runs] }
    # Test::Unit runs the tests of a case in the order of their names.
    @test_case = Class.new(Test::Unit::TestCase) do
      def self.name = "DispatcherStopCase"

      define_method(:test_a_fails) do
        runs.call << "a"
        flunk "killed"
      end

      define_method(:test_b_runs_after) { runs.call << "b" }
    end
  end

  let(:runs) { [] }

  before { Thread.current[:evilution_dispatcher_runs] = runs }
  after { Thread.current[:evilution_dispatcher_runs] = nil }

  describe ".call" do
    it "runs every test without on_fault" do
      result = described_class.call([@test_case], name: "spec")

      expect(result.run_count).to eq(2)
      expect(runs).to eq(%w[a b])
    end

    it "hands on_fault each fault, with the run's result" do
      seen = []

      result = described_class.call([@test_case], name: "spec", on_fault: ->(fault, res) { seen << [fault, res] })

      expect(seen.map(&:first)).to eq(result.faults)
      expect(seen.map(&:last)).to all(be(result))
    end

    it "returns the result of a run that on_fault stopped, with no test run after the stop" do
      stop_once_finished = lambda do |_fault, result|
        result.add_listener(Test::Unit::TestResult::FINISHED) { result.stop }
      end

      result = described_class.call([@test_case], name: "spec", on_fault: stop_once_finished)

      expect(result).to be_a(Test::Unit::TestResult)
      expect(result.run_count).to eq(1)
      expect(result.failures.map(&:test_name)).to eq(["test_a_fails(DispatcherStopCase)"])
      expect(runs).to eq(%w[a])
    end

    it "runs every test again in the next run after a stopped one" do
      described_class.call([@test_case], name: "spec", on_fault: ->(_fault, result) { result.stop })

      result = described_class.call([@test_case], name: "spec")

      expect(result.run_count).to eq(2)
      expect(runs).to eq(%w[a a b])
    end
  end
end
