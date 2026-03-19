# frozen_string_literal: true

require "evilution/isolation/in_process"
require "evilution/isolation/fork"
require "evilution/ast/parser"
require "evilution/mutator/registry"
require "evilution/memory"
require "evilution/result/mutation_result"

require_relative "../support/matchers/memory_leak_matcher"

RSpec.describe "Memory budget", :memory_budget do
  let(:fixture_path) { File.expand_path("../support/fixtures/simple_class.rb", __dir__) }
  let(:parser) { Evilution::AST::Parser.new }
  let(:registry) { Evilution::Mutator::Registry.default }
  let(:stub_test_command) { ->(_m) { { passed: false } } }

  let(:subjects) { parser.call(fixture_path) }
  let(:mutations) { subjects.flat_map { |s| registry.mutations_for(s) } }

  before do
    skip "no mutations found in fixture" if mutations.empty?
  end

  describe "InProcess isolation" do
    let(:isolator) { Evilution::Isolation::InProcess.new }

    it "does not leak memory over repeated mutations" do
      mutation = mutations.first

      expect do
        isolator.call(mutation:, test_command: stub_test_command, timeout: 5)
      end.not_to leak_memory.over(20).by_more_than(10_240)
    end
  end

  describe "Fork isolation" do
    let(:isolator) { Evilution::Isolation::Fork.new }

    it "does not leak memory over repeated mutations" do
      mutation = mutations.first

      expect do
        isolator.call(mutation:, test_command: stub_test_command, timeout: 5)
      end.not_to leak_memory.over(20).by_more_than(10_240)
    end
  end

  describe "mutation generation and stripping" do
    it "does not leak memory when generating and stripping mutations" do
      expect do
        new_subjects = parser.call(fixture_path)
        new_mutations = new_subjects.flat_map { |s| registry.mutations_for(s) }
        new_subjects.each(&:release_node!)
        new_mutations.each(&:strip_sources!)
      end.not_to leak_memory.over(20).by_more_than(10_240)
    end
  end

  describe "parallel pool with compact serialization" do
    it "does not leak memory over repeated batches" do
      pool = Evilution::Parallel::Pool.new(size: 2)
      batch = mutations.first(2)
      skip "need at least 2 mutations" if batch.size < 2

      worker_isolator = Evilution::Isolation::InProcess.new

      expect do
        compact_results = pool.map(batch) do |mutation|
          result = worker_isolator.call(mutation:, test_command: stub_test_command, timeout: 5)
          {
            status: result.status,
            duration: result.duration,
            child_rss_kb: result.child_rss_kb,
            memory_delta_kb: result.memory_delta_kb
          }
        end

        batch.each(&:strip_sources!)
        batch.zip(compact_results).map do |mutation, data|
          Evilution::Result::MutationResult.new(
            mutation:,
            status: data[:status],
            duration: data[:duration],
            child_rss_kb: data[:child_rss_kb],
            memory_delta_kb: data[:memory_delta_kb]
          )
        end
      end.not_to leak_memory.over(10).by_more_than(10_240)
    end
  end
end
