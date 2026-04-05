# frozen_string_literal: true

require "evilution/runner"
require "evilution/memory"

RSpec.describe Evilution::Runner, "per-mutation RSS growth", :memory_budget,
               if: File.exist?("/proc/self/status") && ENV["EVILUTION_RUN_MEMORY_BENCHMARKS"] == "1" do
  let(:fixture_path) { File.expand_path("../support/fixtures/simple_class.rb", __dir__) }
  let(:fixture_spec_path) { File.expand_path("../support/fixtures/simple_class_spec.rb", __dir__) }
  let(:max_growth_per_mutation_kb) { 512 }

  before do
    skip "RSS measurement unavailable" unless Evilution::Memory.rss_kb
  end

  context "with fork isolation (one child per mutation)" do
    let(:config) do
      Evilution::Config.new(
        target_files: [fixture_path],
        spec_files: [fixture_spec_path],
        format: :json,
        timeout: 30,
        quiet: true,
        baseline: false,
        isolation: :fork,
        skip_config_file: true
      )
    end

    it "does not show linear RSS growth in child processes" do
      rss_samples = collect_child_rss(config)
      assert_no_rss_trend(rss_samples, label: "fork isolation")
    end
  end

  context "with parallel workers (persistent child processes)" do
    let(:config) do
      Evilution::Config.new(
        target_files: [fixture_path],
        spec_files: [fixture_spec_path],
        format: :json,
        timeout: 30,
        quiet: true,
        baseline: false,
        jobs: 2,
        skip_config_file: true
      )
    end

    it "does not show linear RSS growth in worker processes" do
      rss_samples = collect_child_rss(config)
      assert_no_rss_trend(rss_samples, label: "parallel workers (jobs=2)")
    end
  end

  private

  def collect_child_rss(run_config)
    rss_samples = []

    on_result = lambda do |result|
      rss_samples << result.child_rss_kb if result.child_rss_kb
    end

    runner = Evilution::Runner.new(config: run_config, on_result: on_result)
    summary = runner.call
    skip "no mutations found in fixture" if summary.total.zero?
    skip "no child RSS data collected" if rss_samples.empty?
    skip "too few samples for trend analysis" if rss_samples.size < 4

    rss_samples
  end

  def rss_growth_per_mutation(rss_samples)
    quarter_size = [rss_samples.size / 4, 1].max
    avg_first = rss_samples[0...quarter_size].sum.to_f / quarter_size
    avg_last = rss_samples[-quarter_size..].sum.to_f / quarter_size
    (avg_last - avg_first) / (rss_samples.size - quarter_size)
  end

  def assert_no_rss_trend(rss_samples, label:)
    growth = rss_growth_per_mutation(rss_samples)

    diagnostics = "[RSS benchmark: #{label}] #{rss_samples.size} mutations, " \
                  "first: #{rss_samples.first} KB, last: #{rss_samples.last} KB, " \
                  "min: #{rss_samples.min} KB, max: #{rss_samples.max} KB, " \
                  "growth/mutation: #{format("%+.1f", growth)} KB"

    warn "\n#{diagnostics}" if ENV["EVILUTION_RSS_BENCH_VERBOSE"]

    expect(growth).to be < max_growth_per_mutation_kb,
                      "Child RSS grew #{format("%.1f", growth)} KB/mutation " \
                      "(limit: #{max_growth_per_mutation_kb} KB/mutation); " \
                      "#{diagnostics}"
  end
end
