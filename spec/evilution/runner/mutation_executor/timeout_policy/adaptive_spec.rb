# frozen_string_literal: true

require "evilution/mutation"
require "evilution/runner/mutation_executor/timeout_policy"

RSpec.describe Evilution::Runner::MutationExecutor::TimeoutPolicy::Adaptive do
  let(:fallback) { Evilution::Runner::MutationExecutor::TimeoutPolicy::Fixed.new(30) }
  let(:resolved) do
    # Frozen, as the run's spec selector hands them out.
    { "lib/foo.rb" => ["spec/foo_spec.rb"].freeze, "lib/bar.rb" => ["spec/bar_spec.rb", "spec/bar/more_spec.rb"].freeze }
  end

  def mutation(file_path = "lib/foo.rb")
    instance_double(Evilution::Mutation, file_path: file_path)
  end

  def policy(durations:, failed: Set.new, factor: 10, floor: 5, ceiling: 60)
    described_class.new(
      fallback: fallback, spec_durations: durations, failed_spec_files: failed,
      spec_selector: ->(path) { resolved[path] }, factor: factor, floor: floor, ceiling: ceiling
    )
  end

  it "scales the baseline time of the mutation's spec file by the factor" do
    expect(policy(durations: { "spec/foo_spec.rb" => 1.2 }).call(mutation)).to be_within(1e-9).of(12.0)
  end

  it "never goes below the floor" do
    expect(policy(durations: { "spec/foo_spec.rb" => 0.05 }).call(mutation)).to eq(5)
  end

  it "never goes above the ceiling" do
    expect(policy(durations: { "spec/foo_spec.rb" => 20.0 }).call(mutation)).to eq(60)
  end

  it "adds up the baseline times of every spec file the mutation runs" do
    durations = { "spec/bar_spec.rb" => 1.0, "spec/bar/more_spec.rb" => 2.0 }

    expect(policy(durations: durations).call(mutation("lib/bar.rb"))).to eq(30.0)
  end

  it "keeps the fallback limit when no spec file resolves" do
    expect(policy(durations: { "spec/foo_spec.rb" => 1.0 }).call(mutation("lib/none.rb"))).to eq(30)
  end

  it "keeps the fallback limit when a resolved spec file has no baseline time" do
    expect(policy(durations: { "spec/bar_spec.rb" => 1.0 }).call(mutation("lib/bar.rb"))).to eq(30)
  end

  # A file that failed in the baseline may have stopped early or timed out, so
  # its time says nothing about how long a full run takes.
  it "keeps the fallback limit when a resolved spec file failed in the baseline" do
    adaptive = policy(durations: { "spec/foo_spec.rb" => 0.1 }, failed: Set["spec/foo_spec.rb"])

    expect(adaptive.call(mutation)).to eq(30)
  end

  it "keeps the fallback limit when any one of several resolved spec files failed in the baseline" do
    durations = { "spec/bar_spec.rb" => 1.0, "spec/bar/more_spec.rb" => 1.0 }

    expect(policy(durations: durations, failed: Set["spec/bar_spec.rb"]).call(mutation("lib/bar.rb"))).to eq(30)
  end

  it "asks the fallback about the mutation at hand" do
    fallback = ->(mut) { mut.file_path == "lib/none.rb" ? 12 : 99 }
    adaptive = described_class.new(fallback: fallback, spec_durations: {}, failed_spec_files: Set.new,
                                   spec_selector: ->(path) { resolved[path] }, factor: 10, floor: 5, ceiling: 60)

    expect(adaptive.call(mutation("lib/none.rb"))).to eq(12)
  end

  it "sets the pool's item timeout to double the longest limit among the mutations" do
    durations = { "spec/foo_spec.rb" => 1.0, "spec/bar_spec.rb" => 1.0, "spec/bar/more_spec.rb" => 1.5 }

    mutations = [mutation, mutation("lib/bar.rb"), mutation].freeze

    expect(policy(durations: durations).item_timeout(mutations)).to eq(50.0)
  end
end
