# frozen_string_literal: true

require "evilution/mutation"
require "evilution/result/mutation_result"
require "evilution/runner/mutation_executor/result_packer"
require "evilution/runner/mutation_executor/result_cache"

RSpec.describe Evilution::Runner::MutationExecutor::ResultCache do
  def mutation(unparseable: false)
    instance_double(Evilution::Mutation, file_path: "lib/foo.rb", unparseable?: unparseable)
  end

  def killed(mut)
    Evilution::Result::MutationResult.new(mutation: mut, status: :killed, duration: 0.1, killing_test: "t", test_command: "c")
  end

  def survived(mut)
    Evilution::Result::MutationResult.new(mutation: mut, status: :survived, duration: 0.1)
  end

  describe "#fetch" do
    it "returns nil when the underlying cache is nil (no caching configured)" do
      expect(described_class.new(nil).fetch(mutation)).to be_nil
    end

    it "returns nil when the cache has no entry for the mutation" do
      backend = instance_double("Cache", fetch: nil)
      expect(described_class.new(backend).fetch(mutation)).to be_nil
    end

    it "returns nil when the cached entry status is not killed or timeout" do
      backend = instance_double("Cache", fetch: { status: :survived, duration: 0.1 })
      expect(described_class.new(backend).fetch(mutation)).to be_nil
    end

    it "rebuilds a MutationResult when status is killed" do
      mut = mutation
      backend = instance_double("Cache", fetch: { status: :killed, duration: 0.2, killing_test: "t", test_command: "c" })
      result = described_class.new(backend).fetch(mut)
      expect(result.status).to eq(:killed)
      expect(result.duration).to eq(0.2)
      expect(result.mutation).to be(mut)
    end

    it "rebuilds a MutationResult when status is timeout" do
      mut = mutation
      backend = instance_double("Cache", fetch: { status: :timeout, duration: 5.0, killing_test: nil, test_command: "c" })
      result = described_class.new(backend).fetch(mut)
      expect(result.status).to eq(:timeout)
    end
  end

  describe "#store" do
    it "is a no-op when the underlying cache is nil" do
      expect { described_class.new(nil).store(mutation, killed(mutation)) }.not_to raise_error
    end

    it "is a no-op for non-killed/timeout results" do
      backend = instance_double("Cache")
      expect(backend).not_to receive(:store)
      described_class.new(backend).store(mutation, survived(mutation))
    end

    it "stores killed results with status/duration/killing_test/test_command" do
      mut = mutation
      backend = instance_double("Cache")
      expect(backend).to receive(:store).with(mut,
                                              status: :killed,
                                              duration: 0.1,
                                              killing_test: "t",
                                              test_command: "c")
      described_class.new(backend).store(mut, killed(mut))
    end
  end

  describe "#partition" do
    let(:packer) { Evilution::Runner::MutationExecutor::ResultPacker.new }

    it "splits batch into uncached_indices and cached_results, encoding cached entries via packer" do
      m1 = mutation                                 # uncached
      m2 = mutation                                 # cache hit
      m3 = mutation(unparseable: true)              # unparseable shortcut
      backend = instance_double("Cache")
      allow(backend).to receive(:fetch).with(m1).and_return(nil)
      allow(backend).to receive(:fetch).with(m2).and_return(status: :killed, duration: 0.3, killing_test: "k", test_command: "c")

      cache = described_class.new(backend)
      uncached_indices, cached_results = cache.partition([m1, m2, m3], packer: packer)

      expect(uncached_indices).to eq([0])
      expect(cached_results.keys).to contain_exactly(1, 2)
      expect(cached_results[1][:status]).to eq(:killed)
      expect(cached_results[2][:status]).to eq(:unparseable)
    end
  end
end
