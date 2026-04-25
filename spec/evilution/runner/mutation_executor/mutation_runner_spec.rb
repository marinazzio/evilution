# frozen_string_literal: true

require "evilution/config"
require "evilution/mutation"
require "evilution/result/mutation_result"
require "evilution/runner/mutation_executor/result_cache"
require "evilution/runner/mutation_executor/mutation_runner"

RSpec.describe Evilution::Runner::MutationExecutor::MutationRunner do
  let(:cfg) { Evilution::Config.new(quiet: true, baseline: false, skip_config_file: true, timeout: 30) }

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

    runner = described_class.new(config: cfg, cache: cache_with, isolator: isolator)
    out = runner.call(mut, integration: ->(_) { "cmd" })
    expect(out.status).to eq(:unparseable)
  end

  it "returns the cached result without calling isolator when cache hit" do
    mut = mutation
    backend = instance_double("Cache", fetch: { status: :killed, duration: 0.2, killing_test: "t", test_command: "c" })
    isolator = double(:isolator)
    expect(isolator).not_to receive(:call)

    runner = described_class.new(config: cfg, cache: cache_with(backend), isolator: isolator)
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

    runner = described_class.new(config: cfg, cache: cache_with(backend), isolator: isolator)
    out = runner.call(mut, integration: integration)
    expect(out.status).to eq(:killed)
  end

  it "does not store survived results in cache" do
    mut = mutation
    backend = instance_double("Cache", fetch: nil)
    expect(backend).not_to receive(:store)
    isolator = double(:isolator)
    allow(isolator).to receive(:call).and_return(survived(mut))

    runner = described_class.new(config: cfg, cache: cache_with(backend), isolator: isolator)
    runner.call(mut, integration: ->(_) { "cmd" })
  end
end
