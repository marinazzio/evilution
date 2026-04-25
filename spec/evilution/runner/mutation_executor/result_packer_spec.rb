# frozen_string_literal: true

require "evilution/mutation"
require "evilution/result/mutation_result"
require "evilution/runner/mutation_executor/result_packer"

RSpec.describe Evilution::Runner::MutationExecutor::ResultPacker do
  let(:packer) { described_class.new }

  let(:mutation) { instance_double(Evilution::Mutation, file_path: "lib/foo.rb") }

  let(:result) do
    Evilution::Result::MutationResult.new(
      mutation: mutation,
      status: :killed,
      duration: 0.5,
      killing_test: "spec/foo_spec.rb:10",
      test_command: "rspec spec/foo_spec.rb",
      child_rss_kb: 1024,
      memory_delta_kb: 256,
      parent_rss_kb: 2048,
      error_message: "msg",
      error_class: "RuntimeError",
      error_backtrace: ["a.rb:1"]
    )
  end

  describe "#compact" do
    it "extracts all transport-relevant fields into a Hash without the mutation" do
      hash = packer.compact(result)

      expect(hash).to eq(
        status: :killed,
        duration: 0.5,
        killing_test: "spec/foo_spec.rb:10",
        test_command: "rspec spec/foo_spec.rb",
        child_rss_kb: 1024,
        memory_delta_kb: 256,
        parent_rss_kb: 2048,
        error_message: "msg",
        error_class: "RuntimeError",
        error_backtrace: ["a.rb:1"]
      )
    end
  end

  describe "#rebuild" do
    it "constructs a MutationResult from a packed Hash plus a mutation" do
      hash = packer.compact(result)
      rebuilt = packer.rebuild(mutation, hash)

      expect(rebuilt.mutation).to be(mutation)
      expect(rebuilt.status).to eq(:killed)
      expect(rebuilt.duration).to eq(0.5)
      expect(rebuilt.killing_test).to eq("spec/foo_spec.rb:10")
      expect(rebuilt.error_class).to eq("RuntimeError")
      expect(rebuilt.error_backtrace).to eq(["a.rb:1"])
    end
  end
end
