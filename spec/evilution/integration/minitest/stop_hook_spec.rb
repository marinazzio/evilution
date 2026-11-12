# frozen_string_literal: true

require "minitest"
require "evilution/integration/minitest"
require "evilution/integration/minitest/stop_hook"

RSpec.describe Evilution::Integration::Minitest::StopHook do
  let(:known_failures) { Evilution::Integration::KnownFailures.new([]) }

  after { described_class.policy = Evilution::Integration::StopPolicy::DISABLED }

  describe ".hook" do
    # Minitest 6 runs each test through Runnable.run(klass, name, reporter);
    # Minitest 5 through run_one_method, its Runnable.run being the suite runner.
    it "overrides the per-test runner of Minitest 6, which has run_suite" do
      skip "Minitest 5 has no run_suite" unless Minitest::Runnable.respond_to?(:run_suite)

      expect(described_class.hook).to be(described_class::Run)
      expect(described_class.hook.instance_method(:run).arity).to eq(3)
    end

    it "overrides run_one_method on Minitest 5, which has no run_suite" do
      allow(Minitest::Runnable).to receive(:respond_to?).and_call_original
      allow(Minitest::Runnable).to receive(:respond_to?).with(:run_suite).and_return(false)

      hook = described_class.hook

      expect(hook.instance_method(:run_one_method).arity).to eq(3)
      expect(hook.instance_methods(false)).to eq([:run_one_method])
    end
  end

  describe ".install!" do
    it "prepends the hook to Minitest::Runnable once, however often it is called" do
      2.times { described_class.install! }

      ancestors = Minitest::Runnable.singleton_class.ancestors

      expect(ancestors.count(described_class.hook)).to eq(1)
      expect(ancestors.index(described_class.hook)).to be < ancestors.index(Minitest::Runnable.singleton_class)
    end
  end

  describe ".policy" do
    it "never stops until a run sets one" do
      expect(described_class.policy).to be(Evilution::Integration::StopPolicy::DISABLED)
    end
  end

  describe "dispatching a runnable" do
    let(:test_class) do
      Class.new(Minitest::Test) do
        i_suck_and_my_tests_are_order_dependent!

        def self.name
          "StopHookProbeTest"
        end

        def test_a_fails
          flunk "killed"
        end

        def test_b_passes
          assert true
        end
      end
    end

    let(:results) { [] }
    let(:reporter) do
      collected = results
      Minitest::AbstractReporter.new.tap do |r|
        r.define_singleton_method(:record) { |result| collected << result.name }
      end
    end

    before { described_class.install! }
    after { Minitest::Runnable.runnables.delete(test_class) }

    def stopped_policy
      Evilution::Integration::StopPolicy.new(enabled: true, known_failures: known_failures).tap do |policy|
        policy.record(id: "AnyTest#test_any")
      end
    end

    # Minitest 6 splits the suite runner off as run_suite; in Minitest 5 run is it.
    def run_suite
      if test_class.respond_to?(:run_suite)
        test_class.run_suite(reporter, {})
      else
        test_class.run(reporter, {})
      end
    end

    it "runs and records no test once the policy has stopped" do
      described_class.policy = stopped_policy

      run_suite

      expect(results).to eq([])
    end

    it "runs every test while the policy has not stopped" do
      described_class.policy = Evilution::Integration::StopPolicy.new(enabled: true, known_failures: known_failures)

      run_suite

      expect(results).to eq(%w[test_a_fails test_b_passes])
    end

    it "runs every test under the policy it starts with" do
      run_suite

      expect(results).to eq(%w[test_a_fails test_b_passes])
    end

    it "skips the tests after the one whose failure stops the policy" do
      policy = Evilution::Integration::StopPolicy.new(enabled: true, known_failures: known_failures)
      detector = Evilution::Integration::MinitestCrashDetector.new
      detector.policy = policy
      described_class.policy = policy
      collected = results
      reporter.define_singleton_method(:record) do |result|
        detector.record(result)
        collected << result.name
      end

      run_suite

      expect(results).to eq(%w[test_a_fails])
      expect(policy).to be_stopped
    end
  end
end
