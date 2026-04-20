# frozen_string_literal: true

require "evilution/ast/parser"
require "evilution/mutator/registry"
require "evilution/parallel/pool"
require "evilution/isolation/fork"
require "evilution/memory"

# Regression guard for EV-6u4b / GH #748: a 250-mutation end-to-end workload
# (parser + registry + Pool + Fork) must stay within fixed peak-RSS budgets.
# Covers parent retention and worker/child growth. Catches regressions in
# mutation lifecycle, isolation cleanup, or per-iteration worker heap growth
# before they reach users.
#
# Gated behind EVILUTION_RUN_MEMORY_BENCHMARKS=1 (same convention as
# runner_rss_benchmark_spec) because forking 250 mutation children plus pool
# workers is expensive for the default CI pipeline.
RSpec.describe "Peak RSS budget for end-to-end 250-mutation workload", :memory_budget,
               if: File.exist?("/proc/self/status") && ENV["EVILUTION_RUN_MEMORY_BENCHMARKS"] == "1" do
  let(:fixture_path) { File.expand_path("../../support/fixtures/memory_check/target.rb", __dir__) }
  let(:parser) { Evilution::AST::Parser.new }
  let(:registry) { Evilution::Mutator::Registry.default }
  let(:stub_test_command) { ->(_m) { { passed: false } } }

  it "stays under the peak RSS delta budgets (parent + worker child)" do
    skip "RSS measurement unavailable" unless Evilution::Memory.rss_kb

    subjects = parser.call(fixture_path)
    mutations = subjects.flat_map { |s| registry.mutations_for(s) }.first(250)
    expect(mutations.size).to eq(250)

    GC.start
    GC.compact if GC.respond_to?(:compact)
    rss_before = Evilution::Memory.rss_kb
    parent_peak = rss_before
    sampler_done = false
    sampler = Thread.new do
      until sampler_done
        current = Evilution::Memory.rss_kb
        parent_peak = current if current && current > parent_peak
        sleep 0.05
      end
    end

    child_rss_samples = []

    begin
      pool = Evilution::Parallel::Pool.new(size: 2)
      worker_isolator = Evilution::Isolation::Fork.new

      results = pool.map(mutations) do |mutation|
        result = worker_isolator.call(mutation: mutation, test_command: stub_test_command, timeout: 5)
        { child_rss_kb: result.child_rss_kb }
      end
      results.each { |entry| child_rss_samples << entry[:child_rss_kb] if entry[:child_rss_kb] }

      mutations.each(&:strip_sources!)
    ensure
      sampler_done = true
      sampler.join
    end

    parent_delta_kb = parent_peak - rss_before
    child_peak_kb = child_rss_samples.max || 0

    # Parent budget: observed ~8 MB at EV-6u4b (2026-04-20). 50 MB allows ~6x
    # headroom and still catches per-mutation retention (200 KB × 250 = 50 MB).
    parent_budget_kb = 50 * 1024
    # Worker-child budget: Fork spawns a fresh child per mutation that inherits
    # the pool worker's heap via COW. Peak child RSS should stay near worker
    # steady-state. 120 MB budget — triggers on persistent inflation of worker
    # or child heap (e.g. retained mutation source strings per iteration).
    child_budget_kb = 120 * 1024

    aggregate_expect_message = lambda do
      "parent delta #{format("%.1f MB", parent_delta_kb / 1024.0)} " \
        "(baseline #{format("%.1f MB", rss_before / 1024.0)}, " \
        "peak #{format("%.1f MB", parent_peak / 1024.0)}, " \
        "budget #{format("%.1f MB", parent_budget_kb / 1024.0)}); " \
        "child peak #{format("%.1f MB", child_peak_kb / 1024.0)} " \
        "(budget #{format("%.1f MB", child_budget_kb / 1024.0)}, " \
        "samples=#{child_rss_samples.size})"
    end

    expect(parent_delta_kb).to(be < parent_budget_kb, &aggregate_expect_message)
    expect(child_peak_kb).to(be < child_budget_kb, &aggregate_expect_message)
  end
end
