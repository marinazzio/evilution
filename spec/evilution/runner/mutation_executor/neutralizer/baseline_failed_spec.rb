# frozen_string_literal: true

require "evilution/config"
require "evilution/mutation"
require "evilution/result/mutation_result"
require "evilution/result/memory_stats"
require "evilution/runner/mutation_executor/neutralizer/baseline_failed"

RSpec.describe Evilution::Runner::MutationExecutor::Neutralizer::BaselineFailed do
  def mutation(file: "lib/foo.rb")
    instance_double(Evilution::Mutation, file_path: file)
  end

  def result(status, known_failures_only: false, **)
    Evilution::Result::MutationResult.new(mutation: mutation, status: status, duration: 0.01,
                                          known_failures_only: known_failures_only, **)
  end

  # A kill in which only examples the baseline already saw failing failed.
  def discounted_kill(**)
    result(:killed, known_failures_only: true, **)
  end

  def baseline(failed_files: ["spec/foo_spec.rb"])
    instance_double("BaselineResult", failed?: true, failed_spec_files: failed_files)
  end

  def neutralizer(spec_files: [], spec_resolver: ->(_f) { "spec/foo_spec.rb" }, fallback_dir: "spec",
                  fallback_to_full_suite: false)
    cfg = Evilution::Config.new(quiet: true, baseline: false, skip_config_file: true, spec_files: spec_files,
                                fallback_to_full_suite: fallback_to_full_suite)
    described_class.new(config: cfg, spec_resolver: spec_resolver, fallback_dir: fallback_dir)
  end

  describe "what it leaves alone" do
    it "keeps a survivor a survivor, even under a red baseline" do
      survivor = result(:survived)

      expect(neutralizer.call(survivor, baseline_result: baseline)).to be(survivor)
    end

    it "keeps a survivor when the run was given its spec files explicitly" do
      survivor = result(:survived)

      expect(neutralizer(spec_files: ["spec/foo_spec.rb"]).call(survivor, baseline_result: baseline)).to be(survivor)
    end

    it "keeps a kill in which something new failed" do
      kill = result(:killed)

      expect(neutralizer.call(kill, baseline_result: baseline)).to be(kill)
    end

    it "keeps results of other statuses, flagged or not" do
      %i[timeout error unresolved equivalent].each do |status|
        other = result(status, known_failures_only: true)

        expect(neutralizer.call(other, baseline_result: baseline)).to be(other)
      end
    end
  end

  describe "a kill in which only already-failing examples failed" do
    it "becomes neutral" do
      out = neutralizer.call(discounted_kill, baseline_result: baseline)

      expect(out.status).to eq(:neutral)
    end

    it "names the red spec file covering the mutated source" do
      out = neutralizer.call(discounted_kill, baseline_result: baseline)

      expect(out.neutral_reason).to eq(Evilution::Result::NeutralReason.baseline_failure("spec/foo_spec.rb"))
    end

    it "picks the red one among several covering spec files" do
      nz = neutralizer(spec_resolver: ->(_f) { ["spec/green_spec.rb", "spec/red_spec.rb"] })

      out = nz.call(discounted_kill, baseline_result: baseline(failed_files: ["spec/red_spec.rb"]))

      expect(out.neutral_reason.detail).to eq("spec/red_spec.rb")
    end

    it "names no spec file when the run was given its spec files explicitly" do
      out = neutralizer(spec_files: ["spec/a_spec.rb", "spec/b_spec.rb"])
            .call(discounted_kill, baseline_result: baseline(failed_files: ["spec/a_spec.rb"]))

      expect(out.status).to eq(:neutral)
      expect(out.neutral_reason).to eq(Evilution::Result::NeutralReason.baseline_failure(nil))
    end

    it "names no spec file when none covering the source was red" do
      out = neutralizer.call(discounted_kill, baseline_result: baseline(failed_files: ["spec/other_spec.rb"]))

      expect(out.status).to eq(:neutral)
      expect(out.neutral_reason.detail).to be_nil
    end

    it "names no spec file when there is no baseline result to consult" do
      out = neutralizer.call(discounted_kill, baseline_result: nil)

      expect(out.status).to eq(:neutral)
      expect(out.neutral_reason.detail).to be_nil
    end

    it "names the fallback directory for an unresolved source when the run falls back to the full suite" do
      nz = neutralizer(spec_resolver: ->(_f) {}, fallback_dir: "test", fallback_to_full_suite: true)

      out = nz.call(discounted_kill, baseline_result: baseline(failed_files: ["test"]))

      expect(out.neutral_reason.detail).to eq("test")
    end

    it "does not name the fallback directory when the run does not fall back" do
      nz = neutralizer(spec_resolver: ->(_f) {}, fallback_dir: "test", fallback_to_full_suite: false)

      out = nz.call(discounted_kill, baseline_result: baseline(failed_files: ["test"]))

      expect(out.neutral_reason.detail).to be_nil
    end

    it "carries the run's duration, command, memory and error over" do
      memory = Evilution::Result::MemoryStats.from_fields(child_rss_kb: 10)
      kill = discounted_kill(test_command: "rspec spec/foo_spec.rb", memory: memory)

      out = neutralizer.call(kill, baseline_result: baseline)

      expect(out.mutation).to be(kill.mutation)
      expect(out.duration).to eq(0.01)
      expect(out.test_command).to eq("rspec spec/foo_spec.rb")
      expect(out.child_rss_kb).to eq(10)
    end

    it "is no longer flagged once neutral" do
      expect(neutralizer.call(discounted_kill, baseline_result: baseline).known_failures_only?).to be(false)
    end
  end
end
