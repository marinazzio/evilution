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

  it "has no item timeout when there is no limit" do
    expect(described_class.new(nil).item_timeout([mutation])).to be_nil
  end
end
