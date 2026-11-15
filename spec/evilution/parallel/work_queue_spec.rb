# frozen_string_literal: true

require "tmpdir"
require "timeout"
require "evilution/parallel/work_queue"
require "evilution/hooks"
require "evilution/worker_database/copies"
require_relative "../../support/fake_active_record"

# This spec covers the public API contract of WorkQueue and a small set of
# end-to-end smoke tests that exercise real Process.fork. Granular coverage of
# the internals lives in per-class specs:
#   - work_queue/worker_stat_spec.rb
#   - work_queue/validators/*_spec.rb
#   - work_queue/channel_spec.rb, work_queue/channel/frame_spec.rb
#   - work_queue/worker_spec.rb, work_queue/worker/loop_spec.rb
#   - work_queue/dispatcher_spec.rb
#   - work_queue/collection_state_spec.rb
RSpec.describe Evilution::Parallel::WorkQueue do
  describe "constants" do
    it "exposes SHUTDOWN, STATS, TIMING_GRACE_PERIOD, and WorkerStat at the public name" do
      expect(described_class::SHUTDOWN).to eq(:__shutdown__)
      expect(described_class::STATS).to eq(:__stats__)
      expect(described_class::TIMING_GRACE_PERIOD).to be_a(Numeric)
      expect(described_class::WorkerStat).to be_a(Class)
    end
  end

  describe "#initialize argument validation (smoke)" do
    it "rejects invalid size via PositiveInt validator" do
      expect { described_class.new(size: 0) }.to raise_error(ArgumentError, /positive integer/)
    end

    it "rejects invalid prefetch via PositiveInt validator" do
      expect { described_class.new(size: 1, prefetch: 0) }.to raise_error(ArgumentError, /prefetch must be a positive integer/)
    end

    it "rejects invalid item_timeout via OptionalPositiveNumber validator" do
      expect { described_class.new(size: 1, item_timeout: -1) }.to raise_error(ArgumentError, /item_timeout/)
    end

    it "rejects invalid worker_max_items via OptionalPositiveInt validator" do
      expect { described_class.new(size: 1, worker_max_items: 0) }.to raise_error(ArgumentError, /worker_max_items/)
    end

    it "accepts valid arguments" do
      queue = described_class.new(size: 2, prefetch: 1, item_timeout: 5, worker_max_items: 3)
      expect(queue).to be_a(described_class)
    end
  end

  describe "#map" do
    it "returns [] for empty input without spawning workers" do
      queue = described_class.new(size: 2)
      expect(queue.map([]) { |n| n }).to eq([])
      expect(queue.worker_stats).to eq([])
    end

    it "executes block for each item and returns results in input order (golden path)" do
      queue = described_class.new(size: 2)
      results = queue.map([1, 2, 3, 4, 5]) { |n| n * 10 }

      expect(results).to eq([10, 20, 30, 40, 50])
    end

    it "streams each result to on_result as it arrives" do
      queue = described_class.new(size: 2)
      streamed = []
      results = queue.map([1, 2, 3], on_result: ->(index, value) { streamed << [index, value] }) { |n| n * 10 }

      expect(streamed).to contain_exactly([0, 10], [1, 20], [2, 30])
      expect(results).to eq([10, 20, 30])
    end

    # on_result waits for the round's workers to have their next item;
    # on_arrival comes first, so what it learns reaches the item sent next.
    it "hands each result to on_arrival before the worker that sent it is given its next item" do
      queue = described_class.new(size: 1)
      arrived = []
      taken = []
      items = Object.new
      items.define_singleton_method(:length) { 3 }
      items.define_singleton_method(:empty?) { false }
      items.define_singleton_method(:[]) do |index|
        taken << arrived.dup
        index
      end

      results = queue.map(items, on_arrival: ->(index, _value) { arrived << index }) { |n| n * 10 }

      expect(results).to eq([0, 10, 20])
      expect(taken).to eq([[], [0], [0, 1]])
    end

    it "serves every item from the same workers instead of spawning per item" do
      queue = described_class.new(size: 2)
      pids = queue.map((1..8).to_a) { |_n| Process.pid }

      expect(pids.uniq.length).to eq(2)
      expect(queue.worker_stats.length).to eq(2)
    end

    it "stops dispatching when on_result answers :stop and leaves no worker behind" do
      queue = described_class.new(size: 2)
      results = Timeout.timeout(10) do
        queue.map((1..20).to_a, on_result: ->(_index, _value) { :stop }) { |n| n }
      end

      expect(results.compact.length).to be_between(1, 4)
      queue.worker_stats.each do |stat|
        expect { Process.wait(stat.pid) }.to raise_error(Errno::ECHILD)
      end
    end

    it "propagates exceptions raised by the user block" do
      queue = described_class.new(size: 2)

      expect do
        queue.map([1, 2, 3]) do |n|
          raise "boom" if n == 2

          n
        end
      end.to raise_error(RuntimeError, "boom")
    end

    it "marks a stuck item with the TIMED_OUT sentinel instead of aborting the run" do
      queue = described_class.new(size: 2, item_timeout: 1)

      results = Timeout.timeout(15) do
        queue.map([0, 10, 20]) do |n|
          sleep 60 if n.zero?
          n
        end
      end

      expect(results[0]).to eq(Evilution::Parallel::WorkQueue::TIMED_OUT)
      expect(results[1..]).to eq([10, 20])
    end

    it "recycles workers after worker_max_items items are completed" do
      queue = described_class.new(size: 1, worker_max_items: 2)
      results = queue.map([1, 2, 3, 4, 5, 6]) { |n| n * 10 }

      expect(results).to eq([10, 20, 30, 40, 50, 60])
      stats = queue.worker_stats
      # More retired stats than worker pool size proves recycling happened.
      expect(stats.length).to be > 1
      expect(stats.map(&:pid).uniq.size).to eq(stats.length)
    end
  end

  describe "#worker_stats" do
    it "returns frozen WorkerStat dups with the correct field types after map" do
      queue = described_class.new(size: 2)
      queue.map([1, 2, 3, 4]) do |_n|
        sleep 0.01
        :done
      end

      stats = queue.worker_stats
      expect(stats).to be_an(Array)
      expect(stats.length).to eq(2)
      stats.each do |stat|
        expect(stat).to be_a(described_class::WorkerStat)
        expect(stat).to be_frozen
        expect(stat.pid).to be_a(Integer)
        expect(stat.items_completed).to be_a(Integer)
        expect(stat.busy_time).to be_a(Float)
        expect(stat.wall_time).to be_a(Float)
        expect(stat.idle_time).to be_a(Float)
        expect(stat.utilization).to be_a(Float)
      end
      expect(stats.sum(&:items_completed)).to eq(4)
    end

    it "returns fresh dups, leaving the internally stored stats unfrozen" do
      queue = described_class.new(size: 1)
      queue.map([1]) { |n| n }

      internal = queue.instance_variable_get(:@worker_stats)
      expect(internal).not_to be_empty
      # worker_stats must dup before freezing, so the stored objects stay mutable.
      expect(internal.first).not_to be_frozen
      queue.worker_stats
      expect(internal.first).not_to be_frozen
    end
  end

  describe "#map cleanup and final timing collection" do
    it "collects final busy/wall timings from workers after the run" do
      queue = described_class.new(size: 1)
      queue.map([1]) do |n|
        sleep 0.05
        n
      end

      stat = queue.worker_stats.first
      # collect_final_timings must drain the worker's STATS frame; otherwise
      # busy_time and wall_time would stay at their 0.0 defaults.
      expect(stat.wall_time).to be > 0.0
      expect(stat.busy_time).to be > 0.0
    end

    # The timings are a courtesy. A frame that cannot be read at this point
    # costs the figures, not the results the run already has.
    it "keeps the results when a worker's final timing frame cannot be read" do
      queue = described_class.new(size: 1)
      original = Evilution::Parallel::WorkQueue::Channel.method(:read)
      calls = 0
      allow(Evilution::Parallel::WorkQueue::Channel).to receive(:read) do |io, **options|
        calls += 1
        raise Evilution::Parallel::WorkQueue::Channel::BadFrame, "garbled" if calls > 1

        original.call(io, **options)
      end

      results = nil
      expect { results = queue.map([1]) { |n| n + 1 } }.not_to raise_error

      expect(results).to eq([2])
      expect(queue.worker_stats.first.wall_time).to eq(0.0)
    end

    # Collecting the timings has a grace period of its own. A read that began
    # inside it must not run past it on a frame that never completes.
    it "reads a final timing frame within what is left of the grace period" do
      queue = described_class.new(size: 1)
      original = Evilution::Parallel::WorkQueue::Channel.method(:read)
      allowed = []
      allow(Evilution::Parallel::WorkQueue::Channel).to receive(:read) do |io, **options|
        allowed << options[:frame_timeout]
        original.call(io, **options)
      end

      queue.map([1]) { |n| n }

      expect(allowed.first).to eq(Evilution::Parallel::WorkQueue::Channel::FRAME_TIMEOUT)
      expect(allowed.last).to be_between(0, described_class::TIMING_GRACE_PERIOD)
    end

    it "reaps every worker process so no zombies remain after map" do
      queue = described_class.new(size: 2)
      queue.map([1, 2, 3, 4]) { |n| n }

      queue.worker_stats.each do |stat|
        expect { Process.wait(stat.pid) }.to raise_error(Errno::ECHILD)
      end
    end

    it "passes hooks through to the forked workers" do
      Dir.mktmpdir do |dir|
        marker = File.join(dir, "fired")
        hooks = Evilution::Hooks.new
        hooks.register(:worker_process_start) { |_| File.write(marker, "yes") }

        queue = described_class.new(size: 1, hooks: hooks)
        queue.map([1]) { |n| n }

        expect(File.exist?(marker)).to be(true)
      end
    end

    it "does not mask the dispatcher's error during cleanup" do
      queue = described_class.new(size: 1)
      faulty = Object.new
      def faulty.run = raise("dispatcher boom")
      def faulty.first_error = nil
      allow(queue).to receive(:build_dispatcher).and_return(faulty)

      expect { queue.map([1]) { |n| n } }.to raise_error(RuntimeError, "dispatcher boom")
    end
  end

  describe "per-worker database copies" do
    around do |example|
      Dir.mktmpdir("evilution-wq-copies") do |dir|
        @dir = dir
        example.run
      end
    end

    let(:copies) { Evilution::WorkerDatabase::Copies.new(root: File.join(@dir, "copies")) }

    before do
      FakeActiveRecord.install(self, root: @dir) do
        { "test" => { "adapter" => "sqlite3", "database" => "db/test.sqlite3" } }
      end
      allow(Evilution::WorkerDatabase::SqliteCopy).to receive(:call) do |_source, destination|
        FileUtils.mkdir_p(File.dirname(destination))
        File.write(destination, "copy")
      end
      allow(Evilution::WorkerDatabase::Copies).to receive(:new).and_return(copies)
    end

    def database_of_worker
      path = ActiveRecord::Base.connection_db_config.configuration_hash[:database]
      [path, File.exist?(path)]
    end

    it "gives each worker its own copy of a shared SQLite database" do
      queue = described_class.new(size: 2, copy_worker_databases: true)
      seen = []

      queue.map([1, 2], on_arrival: ->(_index, value) { seen << value }) { |_n| database_of_worker }

      paths = seen.map(&:first)
      expect(paths).to all(start_with(File.join(@dir, "copies", "worker-")))
      expect(seen.map(&:last)).to all(be(true))
    end

    it "gives a worker that replaces a recycled one a fresh copy" do
      queue = described_class.new(size: 1, worker_max_items: 1, copy_worker_databases: true)
      seen = []

      queue.map([1, 2], on_arrival: ->(_index, value) { seen << value }) { |_n| database_of_worker }

      expect(seen.map(&:first).uniq.length).to eq(2)
      expect(seen.map(&:first)).to all(start_with(File.join(@dir, "copies", "worker-")))
    end

    def copies_on_disk
      [Dir.children(copies.root), "worker-#{Process.pid}"]
    end

    it "deletes the copy of a recycled worker before its replacement starts" do
      queue = described_class.new(size: 1, worker_max_items: 1, copy_worker_databases: true)

      results = queue.map([1, 2, 3]) { |_n| copies_on_disk }

      results.each { |on_disk, own| expect(on_disk).to eq([own]) }
    end

    it "deletes the copy of a worker that died before its replacement starts" do
      queue = described_class.new(size: 1, copy_worker_databases: true)

      results = queue.map([1, 2]) do |n|
        copies_on_disk.tap { exit!(1) if n == 1 }
      end

      expect(results.first).to eq(Evilution::Parallel::WorkQueue::DIED)
      on_disk, own = results.last
      expect(on_disk).to eq([own])
    end

    it "removes the copies once the pass ends" do
      queue = described_class.new(size: 2, copy_worker_databases: true)

      queue.map([1, 2]) { |_n| database_of_worker }

      expect(File.exist?(copies.root)).to be(false)
    end

    it "removes the copies when the pass ends on an error" do
      queue = described_class.new(size: 1, copy_worker_databases: true)

      expect do
        queue.map([1]) do |n|
          database_of_worker
          raise "boom" if n == 1

          n
        end
      end.to raise_error(RuntimeError, "boom")
      expect(File.exist?(copies.root)).to be(false)
    end

    it "copies nothing by default" do
      queue = described_class.new(size: 1)

      results = queue.map([1]) { |_n| database_of_worker }

      expect(results).to eq([["db/test.sqlite3", false]])
      expect(Evilution::WorkerDatabase::Copies).not_to have_received(:new)
    end
  end
end
