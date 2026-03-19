# frozen_string_literal: true

require "tmpdir"

RSpec.describe Evilution::Cache do
  let(:cache_dir) { Dir.mktmpdir("evilution_cache") }
  let(:cache) { described_class.new(cache_dir: cache_dir) }

  after { FileUtils.rm_rf(cache_dir) }

  let(:mutation) do
    double("Mutation",
           file_path: "lib/example.rb",
           original_source: "class Example\n  def foo\n    1 + 2\n  end\nend\n",
           operator_name: "arithmetic_replacement",
           line: 3,
           column: 6)
  end

  let(:result_data) do
    { status: :killed, duration: 0.5, killing_test: "spec/example_spec.rb:10", test_command: "rspec spec/example_spec.rb" }
  end

  describe "#fetch" do
    it "returns nil for uncached mutation" do
      expect(cache.fetch(mutation)).to be_nil
    end

    it "returns cached data for previously stored mutation" do
      cache.store(mutation, result_data)

      cached = cache.fetch(mutation)
      expect(cached[:status]).to eq(:killed)
      expect(cached[:duration]).to eq(0.5)
      expect(cached[:killing_test]).to eq("spec/example_spec.rb:10")
    end

    it "returns nil when source file content changes" do
      cache.store(mutation, result_data)

      changed_mutation = double("Mutation",
                                file_path: "lib/example.rb",
                                original_source: "class Example\n  def foo\n    1 + 3\n  end\nend\n",
                                operator_name: "arithmetic_replacement",
                                line: 3,
                                column: 6)

      expect(cache.fetch(changed_mutation)).to be_nil
    end

    it "returns nil when original_source is nil (stripped mutation)" do
      cache.store(mutation, result_data)

      stripped = double("Mutation",
                        file_path: "lib/example.rb",
                        original_source: nil,
                        operator_name: "arithmetic_replacement",
                        line: 3,
                        column: 6)

      expect(cache.fetch(stripped)).to be_nil
    end
  end

  describe "#store" do
    it "persists data to disk" do
      cache.store(mutation, result_data)

      fresh_cache = described_class.new(cache_dir: cache_dir)
      expect(fresh_cache.fetch(mutation)).not_to be_nil
    end

    it "creates cache directory if missing" do
      nested_dir = File.join(cache_dir, "nested", "dir")
      nested_cache = described_class.new(cache_dir: nested_dir)

      nested_cache.store(mutation, result_data)

      expect(File.directory?(nested_dir)).to be true
    end
  end

  describe "#clear" do
    it "removes all cached data" do
      cache.store(mutation, result_data)
      cache.clear

      expect(cache.fetch(mutation)).to be_nil
    end
  end

  describe "fingerprinting" do
    it "distinguishes mutations on different lines" do
      mutation_line5 = double("Mutation",
                              file_path: "lib/example.rb",
                              original_source: mutation.original_source,
                              operator_name: "arithmetic_replacement",
                              line: 5,
                              column: 6)

      cache.store(mutation, result_data)

      expect(cache.fetch(mutation_line5)).to be_nil
    end

    it "distinguishes mutations with different operators" do
      other_op = double("Mutation",
                        file_path: "lib/example.rb",
                        original_source: mutation.original_source,
                        operator_name: "string_literal",
                        line: 3,
                        column: 6)

      cache.store(mutation, result_data)

      expect(cache.fetch(other_op)).to be_nil
    end
  end

  describe "malformed entries" do
    it "returns nil for entry missing status key" do
      cache.store(mutation, result_data)

      # Corrupt the cache file by removing the status key
      Dir.glob(File.join(cache_dir, "*.json")).each do |path|
        data = JSON.parse(File.read(path))
        data.each_value { |entry| entry.delete("status") if entry.is_a?(Hash) }
        File.write(path, JSON.generate(data))
      end

      expect(cache.fetch(mutation)).to be_nil
    end

    it "returns nil for non-hash entry" do
      cache.store(mutation, result_data)

      Dir.glob(File.join(cache_dir, "*.json")).each do |path|
        data = JSON.parse(File.read(path))
        data.each_key { |k| data[k] = "corrupted" }
        File.write(path, JSON.generate(data))
      end

      expect(cache.fetch(mutation)).to be_nil
    end
  end
end
