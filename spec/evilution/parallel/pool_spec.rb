# frozen_string_literal: true

require "evilution/parallel/pool"

RSpec.describe Evilution::Parallel::Pool do
  subject(:pool) { described_class.new(jobs: 2) }

  # Build real Mutation objects (not doubles) so they survive Marshal serialization
  # across process boundaries. Subject#node is nil here because it is only consumed
  # by the mutator and never accessed by Isolation::Fork or MutationResult.
  let(:subject_obj) do
    Evilution::Subject.new(
      name: "Example#foo",
      file_path: "lib/example.rb",
      line_number: 1,
      source: "def foo; end",
      node: nil
    )
  end

  def build_mutation(index)
    Evilution::Mutation.new(
      subject: subject_obj,
      operator_name: "comparison_replacement",
      original_source: "a > b",
      mutated_source: "a < b",
      file_path: "lib/example.rb",
      line: index
    )
  end

  let(:mutations) { (1..4).map { |i| build_mutation(i) } }

  describe "partition" do
    def build_mutation_for_file(file, line)
      subj = Evilution::Subject.new(
        name: "Example#foo",
        file_path: file,
        line_number: line,
        source: "def foo; end",
        node: nil
      )
      Evilution::Mutation.new(
        subject: subj,
        operator_name: "comparison_replacement",
        original_source: "a > b",
        mutated_source: "a < b",
        file_path: file,
        line: line
      )
    end

    it "distributes mutations round-robin across chunks" do
      all_mutations = (1..5).map { |i| build_mutation_for_file("lib/a.rb", i) }
      chunks = pool.send(:partition, all_mutations, 2)

      # Round-robin: indices 0,2,4 -> chunk 0; indices 1,3 -> chunk 1
      expect(chunks[0].map(&:line)).to eq([1, 3, 5])
      expect(chunks[1].map(&:line)).to eq([2, 4])

      # No mutations lost or duplicated
      expect(chunks.flatten).to match_array(all_mutations)
    end

    it "evenly distributes mutations across chunks" do
      all_mutations = (1..6).map { |i| build_mutation_for_file("lib/a.rb", i) }
      chunks = pool.send(:partition, all_mutations, 3)

      sizes = chunks.map(&:size)
      expect(sizes).to all(eq(2))
    end
  end

  describe "#call" do
    context "with passing test commands" do
      let(:test_command_builder) do
        ->(_mutation) { ->(_m) { { passed: true } } }
      end

      it "returns a MutationResult for every mutation" do
        results = pool.call(mutations: mutations, test_command_builder: test_command_builder, timeout: 10)

        expect(results.size).to eq(4)
        expect(results).to all(be_a(Evilution::Result::MutationResult))
      end

      it "marks all results as survived when tests pass" do
        results = pool.call(mutations: mutations, test_command_builder: test_command_builder, timeout: 10)

        expect(results).to all(be_survived)
      end
    end

    context "with failing test commands" do
      let(:test_command_builder) do
        ->(_mutation) { ->(_m) { { passed: false } } }
      end

      it "marks all results as killed when tests fail" do
        results = pool.call(mutations: mutations, test_command_builder: test_command_builder, timeout: 10)

        expect(results).to all(be_killed)
      end
    end

    context "with an empty mutation list" do
      it "returns an empty array" do
        results = pool.call(mutations: [], test_command_builder: ->(_m) { ->(_m2) {} }, timeout: 10)

        expect(results).to eq([])
      end
    end

    context "with a single worker (jobs: 1)" do
      subject(:single_pool) { described_class.new(jobs: 1) }

      let(:test_command_builder) do
        ->(_mutation) { ->(_m) { { passed: true } } }
      end

      it "still returns results for all mutations" do
        results = single_pool.call(mutations: mutations, test_command_builder: test_command_builder, timeout: 10)

        expect(results.size).to eq(4)
      end
    end

    context "with more workers than mutations" do
      subject(:big_pool) { described_class.new(jobs: 10) }

      let(:small_mutations) { [build_mutation(1), build_mutation(2)] }

      let(:test_command_builder) do
        ->(_mutation) { ->(_m) { { passed: true } } }
      end

      it "returns results for all mutations without error" do
        results = big_pool.call(
          mutations: small_mutations,
          test_command_builder: test_command_builder,
          timeout: 10
        )

        expect(results.size).to eq(2)
      end
    end

    context "verifying parallelism" do
      # Each mutation sleeps 0.3s. With 2 workers handling 2 mutations each in parallel,
      # wall-clock time should be ~0.6s — significantly less than the 1.2s that sequential
      # execution (4 × 0.3s) would take.
      #
      # All mutations use the same file — round-robin partition spreads them across workers,
      # and per-mutation file isolation (via Integration::RSpec temp dirs) prevents conflicts.
      let(:sleep_duration) { 0.3 }
      let(:sequential_lower_bound) { parallel_mutations.size * sleep_duration } # 1.2s

      let(:parallel_mutations) do
        (1..4).map { |i| build_mutation(i) }
      end

      let(:test_command_builder) do
        duration = sleep_duration
        lambda { |_mutation|
          lambda { |_m|
            sleep duration
            { passed: true }
          }
        }
      end

      it "completes faster than sequential execution would" do
        start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        results = pool.call(mutations: parallel_mutations, test_command_builder: test_command_builder, timeout: 10)
        elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start

        expect(results.size).to eq(4)
        expect(elapsed).to be < sequential_lower_bound
      end
    end

    context "when a test command raises an error" do
      let(:test_command_builder) do
        ->(_mutation) { ->(_m) { raise "something went wrong" } }
      end

      it "returns error results instead of crashing" do
        results = pool.call(mutations: mutations, test_command_builder: test_command_builder, timeout: 10)

        expect(results.size).to eq(4)
        expect(results).to all(be_error)
      end
    end
  end
end
