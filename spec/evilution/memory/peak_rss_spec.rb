# frozen_string_literal: true

require "evilution/ast/parser"
require "evilution/mutator/registry"
require "evilution/parallel/pool"
require "evilution/isolation/fork"
require "evilution/memory"

# Regression guard for EV-6u4b / GH #748: a 250-mutation end-to-end workload
# (parser + registry + Pool + Fork) must stay within a fixed peak-RSS budget.
# Catches regressions in mutation lifecycle, isolation cleanup, or worker
# growth before they reach users.
#
# Tagged :slow because it forks dozens of processes and runs ~250 isolations.
# Skip locally with: bundle exec rspec --tag ~slow
RSpec.describe "Peak RSS budget for end-to-end 250-mutation workload",
               :slow, :memory_budget do
  let(:fixture_path) { File.expand_path("../../support/fixtures/memory_check/target.rb", __dir__) }
  let(:parser) { Evilution::AST::Parser.new }
  let(:registry) { Evilution::Mutator::Registry.default }
  let(:stub_test_command) { ->(_m) { { passed: false } } }

  it "stays under the peak RSS delta budget" do
    skip "RSS measurement unavailable" unless Evilution::Memory.rss_kb

    subjects = parser.call(fixture_path)
    mutations = subjects.flat_map { |s| registry.mutations_for(s) }.first(250)
    expect(mutations.size).to eq(250)

    GC.start
    GC.compact if GC.respond_to?(:compact)
    rss_before = Evilution::Memory.rss_kb
    peak = rss_before
    sampler_done = false
    sampler = Thread.new do
      until sampler_done
        current = Evilution::Memory.rss_kb
        peak = current if current && current > peak
        sleep 0.05
      end
    end

    begin
      pool = Evilution::Parallel::Pool.new(size: 2)
      worker_isolator = Evilution::Isolation::Fork.new

      pool.map(mutations) do |mutation|
        result = worker_isolator.call(mutation: mutation, test_command: stub_test_command, timeout: 5)
        { status: result.status, duration: result.duration }
      end

      mutations.each(&:strip_sources!)
    ensure
      sampler_done = true
      sampler.join
    end

    peak_delta_kb = peak - rss_before
    # Budget chosen with ~50% headroom over observed baseline. Lower this if
    # actual usage drops materially; raise only with a concrete justification
    # tied to a feature change.
    # Observed baseline at EV-6u4b (2026-04-20): ~8 MB delta on a 250-mutation
    # toy fixture with stub test_command. Budget set at 50 MB — tight enough to
    # catch a per-iteration retention (e.g. 200 KB/mutation × 250 = 50 MB) yet
    # loose enough to absorb GC and CI variance.
    budget_kb = 50 * 1024

    expect(peak_delta_kb).to be < budget_kb,
                             "peak RSS delta was #{format("%.1f MB", peak_delta_kb / 1024.0)} " \
                             "(baseline #{format("%.1f MB", rss_before / 1024.0)}, " \
                             "peak #{format("%.1f MB", peak / 1024.0)}); " \
                             "budget #{format("%.1f MB", budget_kb / 1024.0)}"
  end
end
