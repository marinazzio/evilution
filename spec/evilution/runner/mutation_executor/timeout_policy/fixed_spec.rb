# frozen_string_literal: true

require "evilution/mutation"
require "evilution/runner/mutation_executor/timeout_policy"

RSpec.describe Evilution::Runner::MutationExecutor::TimeoutPolicy::Fixed do
  let(:mutation) { instance_double(Evilution::Mutation, file_path: "lib/foo.rb") }

  it "gives every mutation the same limit" do
    expect(described_class.new(30).call(mutation)).to eq(30)
  end

  it "sets the pool's item timeout to double the limit" do
    expect(described_class.new(9).item_timeout([mutation])).to eq(18)
  end

  it "is frozen, so workers forked from the parent share one unchanging limit" do
    expect(described_class.new(30)).to be_frozen
  end

  it "reports a timeout under its own limit without confirming it" do
    expect(described_class.new(30).confirmation_limit(mutation)).to be_nil
  end

  it "is the final limit a mutation runs under" do
    expect(described_class.new(30).final_limit(mutation)).to eq(30)
  end

  it "has no item timeout when there is no limit" do
    expect(described_class.new(nil).item_timeout([mutation])).to be_nil
  end

  it "has no item timeout when there is no mutation to wait on" do
    expect(described_class.new(30).item_timeout([])).to be_nil
  end

  it "has no item timeout for several mutations without a limit" do
    expect(described_class.new(nil).item_timeout([mutation, mutation])).to be_nil
  end
end
