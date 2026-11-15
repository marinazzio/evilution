# frozen_string_literal: true

require "evilution/config"
require "evilution/mutation"
require "evilution/result/mutation_result"
require "evilution/runner/mutation_executor/result_cache"
require "evilution/runner/mutation_executor/mutation_runner"
require "evilution/runner/mutation_executor/timeout_policy"

RSpec.describe Evilution::Runner::MutationExecutor::MutationRunner do
  let(:fixed_policy) { Evilution::Runner::MutationExecutor::TimeoutPolicy::Fixed.new(30) }

  def mutation(unparseable: false)
    instance_double(Evilution::Mutation, file_path: "lib/foo.rb", unparseable?: unparseable)
  end

  def killed(mut)
    Evilution::Result::MutationResult.new(mutation: mut, status: :killed, duration: 0.1, killing_test: "t", test_command: "c")
  end

  def survived(mut)
    Evilution::Result::MutationResult.new(mutation: mut, status: :survived, duration: 0.1)
  end

  def cache_with(backend = nil)
    Evilution::Runner::MutationExecutor::ResultCache.new(backend)
  end

  it "returns an :unparseable result when mutation.unparseable? is true (no isolator call)" do
    mut = mutation(unparseable: true)
    isolator = double(:isolator)
    expect(isolator).not_to receive(:call)

    runner = described_class.new(cache: cache_with, isolator: isolator, timeout_policy: fixed_policy)
    out = runner.call(mut, integration: ->(_) { "cmd" })
    expect(out.status).to eq(:unparseable)
  end

  it "returns the cached result without calling isolator when cache hit" do
    mut = mutation
    backend = instance_double("Cache", fetch: { status: :killed, duration: 0.2, killing_test: "t", test_command: "c" })
    isolator = double(:isolator)
    expect(isolator).not_to receive(:call)

    runner = described_class.new(cache: cache_with(backend), isolator: isolator, timeout_policy: fixed_policy)
    out = runner.call(mut, integration: ->(_) { "cmd" })
    expect(out.status).to eq(:killed)
    expect(out.duration).to eq(0.2)
  end

  it "calls isolator on cache miss and stores killed result back into cache" do
    mut = mutation
    backend = instance_double("Cache", fetch: nil)
    expect(backend).to receive(:store).with(mut, hash_including(status: :killed))
    isolator = double(:isolator)
    integration = ->(_) { "cmd" }

    expect(isolator).to receive(:call) do |mutation:, test_command:, timeout:|
      expect(mutation).to be(mut)
      expect(test_command.call(:m)).to eq("cmd")
      expect(timeout).to eq(30)
      killed(mut)
    end

    runner = described_class.new(cache: cache_with(backend), isolator: isolator, timeout_policy: fixed_policy)
    out = runner.call(mut, integration: integration)
    expect(out.status).to eq(:killed)
  end

  it "runs the mutation under the limit the timeout policy gives it" do
    mut = mutation
    isolator = double(:isolator)
    allow(isolator).to receive(:call).and_return(killed(mut))
    policy = Class.new(Evilution::Runner::MutationExecutor::TimeoutPolicy::Base) do
      define_method(:call) { |m| m.equal?(mut) ? 7.5 : 99 }
    end.new

    runner = described_class.new(cache: cache_with, isolator: isolator, timeout_policy: policy)
    runner.call(mut, integration: ->(_) { "cmd" })

    expect(isolator).to have_received(:call).with(hash_including(timeout: 7.5))
  end

  it "records the limit on a timed-out result" do
    mut = mutation
    isolator = double(:isolator)
    allow(isolator).to receive(:call).and_return(
      Evilution::Result::MutationResult.new(mutation: mut, status: :timeout, duration: 7.6)
    )
    policy = Evilution::Runner::MutationExecutor::TimeoutPolicy::Fixed.new(7.5)

    out = described_class.new(cache: cache_with, isolator: isolator, timeout_policy: policy)
                         .call(mut, integration: ->(_) { "cmd" })

    expect([out.status, out.duration, out.time_limit]).to eq([:timeout, 7.6, 7.5])
  end

  it "records no limit on a result that finished in time" do
    mut = mutation
    isolator = double(:isolator)
    allow(isolator).to receive(:call).and_return(killed(mut))

    out = described_class.new(cache: cache_with, isolator: isolator, timeout_policy: fixed_policy).call(mut, integration: ->(_) { "cmd" })

    expect(out.time_limit).to be_nil
  end

  it "re-runs a cached timeout that the mutation's limit now leaves more time for" do
    mut = mutation
    backend = instance_double("Cache", fetch: { status: :timeout, duration: 10.0, time_limit: 10 })
    allow(backend).to receive(:store)
    isolator = double(:isolator)
    allow(isolator).to receive(:call).and_return(killed(mut))

    out = described_class.new(cache: cache_with(backend), isolator: isolator, timeout_policy: fixed_policy)
                         .call(mut, integration: ->(_) { "cmd" })

    expect(out.status).to eq(:killed)
    expect(backend).to have_received(:store).with(mut, hash_including(status: :killed))
  end

  it "reuses a cached timeout that ran under at least the mutation's final limit" do
    mut = mutation
    backend = instance_double("Cache")
    allow(backend).to receive(:fetch).with(mut).and_return(status: :timeout, duration: 30.0, time_limit: 30)
    isolator = double(:isolator)
    allow(isolator).to receive(:call)
    policy = Class.new(Evilution::Runner::MutationExecutor::TimeoutPolicy::Base) do
      define_method(:call) { |m| m.equal?(mut) ? 10 : 99 }
      define_method(:confirmation_limit) { |m| m.equal?(mut) ? 30 : 99 }
    end.new

    out = described_class.new(cache: cache_with(backend), isolator: isolator, timeout_policy: policy)
                         .call(mut, integration: ->(_) { "cmd" })

    expect([out.status, out.time_limit]).to eq([:timeout, 30])
    expect(isolator).not_to have_received(:call)
  end

  it "stores the limit a timeout ran under with it" do
    mut = mutation
    backend = instance_double("Cache", fetch: nil)
    allow(backend).to receive(:store)
    isolator = double(:isolator)
    allow(isolator).to receive(:call).and_return(
      Evilution::Result::MutationResult.new(mutation: mut, status: :timeout, duration: 30.2)
    )

    described_class.new(cache: cache_with(backend), isolator: isolator, timeout_policy: fixed_policy)
                   .call(mut, integration: ->(_) { "cmd" })

    expect(backend).to have_received(:store).with(mut, hash_including(status: :timeout, time_limit: 30))
  end

  it "confirms a timeout under a shorter limit before reporting it" do
    mut = mutation
    isolator = double(:isolator)
    allow(isolator).to receive(:call).and_return(
      Evilution::Result::MutationResult.new(mutation: mut, status: :timeout, duration: 10.0), killed(mut)
    )
    policy = Class.new(Evilution::Runner::MutationExecutor::TimeoutPolicy::Base) do
      define_method(:call) { |_m| 10 }
      define_method(:confirmation_limit) { |_m| 30 }
    end.new

    out = described_class.new(cache: cache_with, isolator: isolator, timeout_policy: policy)
                         .call(mut, integration: ->(_) { "cmd" })

    expect(out.status).to eq(:killed)
    expect(isolator).to have_received(:call).with(hash_including(timeout: 30))
  end

  it "does not store survived results in cache" do
    mut = mutation
    backend = instance_double("Cache", fetch: nil)
    expect(backend).not_to receive(:store)
    isolator = double(:isolator)
    allow(isolator).to receive(:call).and_return(survived(mut))

    runner = described_class.new(cache: cache_with(backend), isolator: isolator, timeout_policy: fixed_policy)
    runner.call(mut, integration: ->(_) { "cmd" })
  end
end
