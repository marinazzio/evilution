# frozen_string_literal: true

require "evilution/mutation"
require "evilution/result/mutation_result"
require "evilution/runner/mutation_executor/timed_run"
require "evilution/runner/mutation_executor/timeout_policy"

RSpec.describe Evilution::Runner::MutationExecutor::TimedRun do
  let(:mutation) { instance_double(Evilution::Mutation, file_path: "lib/foo.rb") }
  # A plain object, not a lambda: argument matching compares with ===, which a
  # lambda answers by being called, so it would match any test command.
  let(:test_command) { Object.new }

  # A policy that gives `limit` to this mutation and confirms its timeout with
  # `confirm`, and something else entirely to any other.
  def policy(limit:, confirm: nil)
    own = mutation
    Class.new(Evilution::Runner::MutationExecutor::TimeoutPolicy::Base) do
      define_method(:call) { |m| m.equal?(own) ? limit : 999 }
      define_method(:confirmation_limit) { |m| m.equal?(own) ? confirm : 999 }
    end.new
  end

  def result(status, duration, **rest)
    Evilution::Result::MutationResult.new(mutation: mutation, status: status, duration: duration, **rest)
  end

  # An isolator that answers each call with the next of `results`, recording
  # the limit it was given.
  def isolator(*results)
    double(:isolator).tap do |iso|
      allow(iso).to receive(:call) { results.shift }
    end
  end

  it "runs the mutation once under the policy's limit and hands back what finished in time" do
    iso = isolator(result(:killed, 0.4, killing_test: "t"))

    out = described_class.new(isolator: iso, timeout_policy: policy(limit: 10, confirm: 30)).call(mutation, test_command)

    expect([out.status, out.duration, out.time_limit, out.timings]).to eq([:killed, 0.4, nil, nil])
    expect(iso).to have_received(:call).once
    expect(iso).to have_received(:call).with(mutation: mutation, test_command: test_command, timeout: 10)
  end

  it "records the limit on a timeout the policy does not confirm" do
    iso = isolator(result(:timeout, 30.1))

    out = described_class.new(isolator: iso, timeout_policy: policy(limit: 30)).call(mutation, test_command)

    expect([out.status, out.duration, out.time_limit]).to eq([:timeout, 30.1, 30])
    expect(iso).to have_received(:call).once
  end

  # A mutant that slows the code down can fail its test after a short limit
  # ran out; reporting a timeout there would hide a kill the fixed limit sees.
  it "runs a timed-out mutation again under the confirmation limit and reports that run" do
    iso = isolator(result(:timeout, 10.25), result(:killed, 15.5, killing_test: "t"))

    out = described_class.new(isolator: iso, timeout_policy: policy(limit: 10, confirm: 30)).call(mutation, test_command)

    expect([out.status, out.killing_test, out.time_limit]).to eq([:killed, "t", nil])
    expect(iso).to have_received(:call).with(mutation: mutation, test_command: test_command, timeout: 10).ordered
    expect(iso).to have_received(:call).with(mutation: mutation, test_command: test_command, timeout: 30).ordered
  end

  it "counts both runs in the duration and names the first among the timings" do
    iso = isolator(result(:timeout, 10.25), result(:killed, 15.5))

    out = described_class.new(isolator: iso, timeout_policy: policy(limit: 10, confirm: 30)).call(mutation, test_command)

    expect([out.duration, out.timings.to_h]).to eq([25.75, { adaptive_timeout: 10.25 }])
  end

  it "reports a timeout that the confirmation run used up too, with the confirmation limit" do
    iso = isolator(result(:timeout, 10.25), result(:timeout, 30.5))

    out = described_class.new(isolator: iso, timeout_policy: policy(limit: 10, confirm: 30)).call(mutation, test_command)

    expect([out.status, out.duration, out.time_limit]).to eq([:timeout, 40.75, 30])
  end
end
