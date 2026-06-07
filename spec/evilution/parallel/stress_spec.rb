# frozen_string_literal: true

require "spec_helper"
require "timeout"
require "evilution/parallel/work_queue"
require "evilution/parallel/pool"
require "evilution/isolation/fork"
require "evilution/ast/parser"
require "evilution/mutator/registry"

# Stress / load coverage for Parallel::WorkQueue + Isolation::Fork (EV-axze).
#
# These specs deliberately push the work queue and fork isolation far beyond the
# small fixtures used by the per-class specs: thousands of items at -j8+, many
# workers stuck or dying simultaneously, sustained repeated load, and hundreds of
# real forked mutation runs mixing fast and blocking work. They assert the
# invariants that matter under load -- correct results, no deadlocks (wrapped in
# Timeout), no zombie/unreaped workers, no FD leaks, bounded memory growth.
#
# Tagged :stress, so excluded from the default run. Execute via `rake stress`
# (sets RUN_STRESS) or `RUN_STRESS=1 rspec spec/evilution/parallel/stress_spec.rb`.
# Scale knobs are ENV-tunable for slower CI hardware (see StressParams).
module StressParams
  JOBS        = Integer(ENV.fetch("STRESS_JOBS", "8"))
  ITEMS       = Integer(ENV.fetch("STRESS_ITEMS", "10000"))
  FORK_MUTS   = Integer(ENV.fetch("STRESS_FORK_MUTS", "300"))
  RUN_TIMEOUT = Integer(ENV.fetch("STRESS_RUN_TIMEOUT", "120"))
end

RSpec.describe "parallel/isolation stress", :stress do
  let(:wq)          { Evilution::Parallel::WorkQueue }
  let(:jobs)        { StressParams::JOBS }
  let(:items)       { StressParams::ITEMS }
  let(:fork_muts)   { StressParams::FORK_MUTS }
  let(:run_timeout) { StressParams::RUN_TIMEOUT }

  def proc_fd_supported?
    File.directory?("/proc/#{Process.pid}/fd")
  end

  def open_fd_count
    Dir.children("/proc/#{Process.pid}/fd").size
  end

  # Every worker the queue ever ran (live + retired) must be reaped: a surviving
  # entry means a zombie or a process that outlived the run.
  def expect_no_zombies(pool_or_queue)
    pool_or_queue.worker_stats.each do |stat|
      expect { Process.wait(stat.pid) }
        .to raise_error(Errno::ECHILD), "worker pid #{stat.pid} left unreaped (zombie)"
    end
  end

  describe "high concurrency + large item count" do
    it "processes #{StressParams::ITEMS} items across #{StressParams::JOBS} workers in order, with recycling and no zombies" do
      queue = wq.new(size: jobs, worker_max_items: 500)

      results = Timeout.timeout(run_timeout) do
        queue.map((1..items).to_a) { |n| n * 2 }
      end

      expect(results).to eq((1..items).map { |n| n * 2 })

      stats = queue.worker_stats
      expect(stats.sum(&:items_completed)).to eq(items)
      # worker_max_items forces recycling under load, so more workers retired
      # than the pool size, and each carries a distinct pid.
      expect(stats.length).to be >= jobs
      expect(stats.map(&:pid).uniq.size).to eq(stats.length)

      expect_no_zombies(queue)
    end
  end

  describe "file descriptor stability" do
    it "does not leak FDs across repeated high-load maps" do
      skip "requires /proc/<pid>/fd" unless proc_fd_supported?

      # Warm up so first-run lazy allocations don't count as a leak.
      wq.new(size: jobs).map((1..1000).to_a) { |n| n }
      GC.start
      before = open_fd_count

      5.times do
        queue = wq.new(size: jobs)
        Timeout.timeout(run_timeout) { queue.map((1..1000).to_a) { |n| n } }
      end

      GC.start
      after = open_fd_count
      expect(after - before).to be <= 8
    end
  end

  describe "per-item timeout recovery under cascade (EV-gl1e regression)" do
    it "kills and recycles every simultaneously-stuck worker without aborting the run" do
      blocking = jobs # one stuck item seeded per worker, all at once
      fast     = 200
      input    = (0...(blocking + fast)).to_a

      queue = wq.new(size: jobs, prefetch: 1, item_timeout: 0.3)

      results = Timeout.timeout(run_timeout) do
        queue.map(input) do |n|
          sleep 600 if n < blocking # never returns -> must be timed out + killed
          n * 10
        end
      end

      blocking.times { |i| expect(results[i]).to eq(wq::TIMED_OUT) }
      (blocking...input.length).each { |i| expect(results[i]).to eq(i * 10) }

      expect_no_zombies(queue)
    end
  end

  describe "worker death recovery under cascade" do
    it "marks in-flight items DIED and continues when many workers die mid-item" do
      dying = jobs
      fast  = 200
      input = (0...(dying + fast)).to_a

      queue = wq.new(size: jobs, prefetch: 1, item_timeout: 30)

      results = Timeout.timeout(run_timeout) do
        queue.map(input) do |n|
          exit!(0) if n < dying # abrupt worker death, no result produced
          n + 1
        end
      end

      dying.times { |i| expect(results[i]).to eq(wq::DIED) }
      (dying...input.length).each { |i| expect(results[i]).to eq(i + 1) }

      expect_no_zombies(queue)
    end
  end

  describe "deadline precision" do
    it "does not spuriously time out fast items under heavy scheduling churn" do
      count = 2000
      queue = wq.new(size: jobs, item_timeout: 5)

      results = Timeout.timeout(run_timeout) do
        queue.map((1..count).to_a) do |n|
          sleep 0.001
          n
        end
      end

      expect(results).to eq((1..count).to_a)
      expect(results).not_to include(wq::TIMED_OUT)
    end
  end

  describe "memory stability under sustained load" do
    it "keeps RSS growth bounded across many parallel maps" do
      skip "RSS measurement requires /proc" unless Evilution::Memory.rss_kb

      run_one = -> { wq.new(size: jobs).map((1..500).to_a) { |n| n * 2 } }

      run_one.call # warm up before baseline
      GC.start
      GC.compact
      before = Evilution::Memory.rss_kb

      15.times { Timeout.timeout(run_timeout) { run_one.call } }

      GC.start
      GC.compact
      after = Evilution::Memory.rss_kb

      growth_mb = (after - before) / 1024.0
      expect(growth_mb).to be <= 20.0
    end
  end

  describe "real Fork isolation under load" do
    let(:fixture) { File.expand_path("../../support/fixtures/simple_class.rb", __dir__) }

    # Build `count` real mutations by cycling the fixture's generated mutations,
    # so the run drives genuine source surgery + fork-per-mutation under -j.
    def build_mutations(count)
      parser   = Evilution::AST::Parser.new
      registry = Evilution::Mutator::Registry.default
      base     = parser.call(fixture).flat_map { |subject| registry.mutations_for(subject) }
      raise "fixture produced no mutations" if base.empty?

      Array.new(count) { |i| base[i % base.length] }
    end

    it "runs #{StressParams::FORK_MUTS} forked mutations at -j#{StressParams::JOBS}, mixing timeouts, with no zombies or FD leak" do
      skip "requires /proc/<pid>/fd" unless proc_fd_supported?

      mutations = build_mutations(fork_muts)
      pool      = Evilution::Parallel::Pool.new(size: jobs)

      GC.start
      fd_before = open_fd_count

      results = Timeout.timeout(run_timeout) do
        pool.map(mutations.each_with_index.to_a) do |(mutation, index)|
          isolator = Evilution::Isolation::Fork.new
          if (index % 25).zero?
            # blocking child: sleeps well past the timeout -> killed -> :timeout
            isolator.call(mutation: mutation, test_command: ->(_m) { sleep 30 }, timeout: 0.3)
          else
            isolator.call(mutation: mutation, test_command: ->(_m) { { passed: false } }, timeout: 5)
          end
        end
      end

      expect(results.size).to eq(fork_muts)
      statuses = results.map(&:status)
      expect(statuses).to all(be_a(Symbol))
      expect(statuses).to include(:timeout) # blocking children were reaped as timeouts

      expect_no_zombies(pool)

      GC.start
      fd_after = open_fd_count
      expect(fd_after - fd_before).to be <= 16
    end
  end
end
