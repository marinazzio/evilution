# frozen_string_literal: true

require "spec_helper"
require "timeout"
require "evilution/parallel/work_queue/worker"
require "evilution/parallel/work_queue/worker/loop"

RSpec.describe Evilution::Parallel::WorkQueue::Worker do
  def process_alive?(pid)
    Process.kill(0, pid)
    true
  rescue Errno::ESRCH
    false
  rescue Errno::EPERM
    true
  end

  def wait_until(timeout: 8)
    Timeout.timeout(timeout) do
      sleep(0.05) until yield
    end
  end

  describe "#kill terminates the whole process group" do
    it "kills grandchildren forked by the worker block, not just the worker" do
      Dir.mktmpdir do |dir|
        pidfile = File.join(dir, "grandchild.pid")
        gpid = nil
        begin
          worker = described_class.spawn(worker_index: 0, hooks: nil) do |_x|
            grandchild = fork { sleep 60 }
            File.write(pidfile, grandchild.to_s)
            sleep 60
          end
          worker.send_item(0, :go)

          wait_until { File.exist?(pidfile) && !File.empty?(pidfile) }
          gpid = File.read(pidfile).to_i
          expect(process_alive?(gpid)).to be(true)

          worker.kill
          worker.reap

          wait_until { !process_alive?(gpid) }
          expect(process_alive?(gpid)).to be(false)
        ensure
          begin
            Process.kill("KILL", gpid) if gpid
          rescue Errno::ESRCH
            nil
          end
        end
      end
    end
  end

  describe ".spawn + lifecycle" do
    it "forks a child, processes one item, retires cleanly" do
      worker = described_class.spawn(worker_index: 0, hooks: nil) { |x| x * 2 }
      worker.send_item(0, 21)

      message = nil
      Timeout.timeout(5) do
        message = worker.read_result until message
      end
      expect(message).to eq([0, :ok, 42])

      worker.items_completed += 1
      worker.pending -= 1

      stat = worker.retire
      expect(stat).to be_a(Evilution::Parallel::WorkQueue::WorkerStat)
      expect(stat.pid).to eq(worker.pid)
      expect(stat.items_completed).to eq(1)
      expect(stat.busy_time).to be >= 0.0
      expect(stat.wall_time).to be >= 0.0
    end

    it "sets TEST_ENV_NUMBER per parallel_tests convention (slot 0 -> empty, slot 1 -> 2)" do
      worker = described_class.spawn(worker_index: 0, hooks: nil) { |_| ENV.fetch("TEST_ENV_NUMBER", nil) }
      worker.send_item(0, nil)
      msg = nil
      Timeout.timeout(5) { msg = worker.read_result until msg }
      expect(msg[2]).to eq("")
      worker.items_completed += 1
      worker.pending -= 1
      worker.retire

      worker2 = described_class.spawn(worker_index: 1, hooks: nil) { |_| ENV.fetch("TEST_ENV_NUMBER", nil) }
      worker2.send_item(0, nil)
      msg2 = nil
      Timeout.timeout(5) { msg2 = worker2.read_result until msg2 }
      expect(msg2[2]).to eq("2")
      worker2.items_completed += 1
      worker2.pending -= 1
      worker2.retire
    end

    it "redirects stderr to per-pid file under ChildOutput.log_dir when set" do
      Dir.mktmpdir do |dir|
        Evilution::ChildOutput.log_dir = dir
        worker = described_class.spawn(worker_index: 0, hooks: nil) do |x|
          warn "noisy-#{x}"
          x
        end
        worker.send_item(0, "init")
        msg = nil
        Timeout.timeout(5) { msg = worker.read_result until msg }
        expect(msg[2]).to eq("init")
        worker.items_completed += 1
        worker.pending -= 1
        worker.retire

        err_file = File.join(dir, "#{worker.pid}.err")
        expect(File.exist?(err_file)).to be(true)
        expect(File.read(err_file)).to include("noisy-init")
      ensure
        Evilution::ChildOutput.log_dir = nil
      end
    end
  end

  describe "#initialize state" do
    it "initializes counters and timings, exposes worker_index and res_io" do
      worker = described_class.spawn(worker_index: 3, hooks: nil) { |x| x }
      begin
        expect(worker.worker_index).to eq(3)
        expect(worker.items_completed).to eq(0)
        expect(worker.pending).to eq(0)
        expect(worker.busy_time).to eq(0.0)
        expect(worker.wall_time).to eq(0.0)
        expect(worker.res_io).to be_a(IO)
        expect(worker.res_io.closed?).to be(false)
      ensure
        worker.shutdown
        worker.close_pipes
        worker.reap
      end
    end
  end

  describe "#send_item" do
    it "increments pending each time an item is enqueued" do
      worker = described_class.spawn(worker_index: 0, hooks: nil) { |x| x }
      begin
        expect { worker.send_item(0, 1) }.to change(worker, :pending).from(0).to(1)
        expect { worker.send_item(1, 2) }.to change(worker, :pending).from(1).to(2)
      ensure
        worker.shutdown
        worker.close_pipes
        worker.reap
      end
    end
  end

  describe "#close_pipes" do
    it "closes res_io and the command pipe" do
      worker = described_class.spawn(worker_index: 0, hooks: nil) { |x| x }
      worker.shutdown
      worker.close_pipes
      worker.reap
      expect(worker.res_io.closed?).to be(true)
      expect { worker.send_item(0, 1) }.to raise_error(IOError)
    end
  end

  describe "#reap" do
    it "waits for the child so it is no longer a child process" do
      worker = described_class.spawn(worker_index: 0, hooks: nil) { |x| x }
      worker.shutdown
      worker.close_pipes
      worker.reap
      expect { Process.wait(worker.pid) }.to raise_error(Errno::ECHILD)
    end
  end

  describe "#retire" do
    it "captures real busy and wall timings from a worker that did work" do
      worker = described_class.spawn(worker_index: 0, hooks: nil) { |_| sleep(0.05) }
      worker.send_item(0, nil)
      msg = nil
      Timeout.timeout(5) { msg = worker.read_result until msg }
      expect(msg[1]).to eq(:ok)
      worker.items_completed += 1
      worker.pending -= 1

      stat = worker.retire
      expect(stat.busy_time).to be > 0.0
      expect(stat.wall_time).to be > 0.0
      expect(worker.busy_time).to be > 0.0
      expect(worker.wall_time).to be > 0.0
    end

    it "closes pipes and reaps the child" do
      worker = described_class.spawn(worker_index: 0, hooks: nil) { |x| x }
      worker.retire
      expect(worker.res_io.closed?).to be(true)
      expect { Process.wait(worker.pid) }.to raise_error(Errno::ECHILD)
    end

    it "returns zero timings without raising when the child was killed" do
      worker = described_class.spawn(worker_index: 0, hooks: nil) { |x| x }
      worker.kill
      begin
        Process.wait(worker.pid)
      rescue Errno::ECHILD
        nil
      end
      stat = nil
      Timeout.timeout(10) { stat = worker.retire }
      expect(stat.busy_time).to eq(0.0)
      expect(stat.wall_time).to eq(0.0)
    end

    it "returns zero timings without raising when a non-stats frame is drained" do
      worker = described_class.spawn(worker_index: 0, hooks: nil) { |x| x * 10 }
      worker.send_item(0, 5)
      # Deliberately do not read the result; retire's drain must encounter the
      # [index, :ok, value] frame, recognise it is not a STATS frame, and
      # fall back to zero timings.
      stat = nil
      Timeout.timeout(10) { stat = worker.retire }
      expect(stat.busy_time).to eq(0.0)
      expect(stat.wall_time).to eq(0.0)
    end
  end

  describe "child pipe hygiene" do
    it "child observes EOF on the command pipe once the parent closes it" do
      worker = described_class.spawn(worker_index: 0, hooks: nil) { |x| x }
      begin
        worker.close_pipes
        Timeout.timeout(8) { Process.wait(worker.pid) }
      rescue Timeout::Error
        Process.kill("KILL", worker.pid)
        raise
      ensure
        begin
          Process.wait(worker.pid)
        rescue Errno::ECHILD
          nil
        end
      end
    end

    it "parent observes EOF on the result pipe after the child exits" do
      worker = described_class.spawn(worker_index: 0, hooks: nil) { |x| x }
      worker.kill
      begin
        Process.wait(worker.pid)
      rescue Errno::ECHILD
        nil
      end
      result = :unset
      Timeout.timeout(5) { result = worker.read_result }
      expect(result).to be_nil
      worker.close_pipes
    end
  end

  describe "#shutdown swallows Errno::EPIPE" do
    it "does not raise when child has already exited" do
      worker = described_class.spawn(worker_index: 0, hooks: nil) { |x| x }
      begin
        worker.kill
        begin
          Process.wait(worker.pid)
        rescue Errno::ECHILD
          nil
        end
        expect { worker.shutdown }.not_to raise_error
      ensure
        worker.close_pipes
      end
    end
  end

  describe "#kill swallows Errno::ESRCH" do
    it "does not raise when child has already exited" do
      worker = described_class.spawn(worker_index: 0, hooks: nil) { |x| x }
      worker.shutdown
      worker.close_pipes
      worker.reap
      expect { worker.kill }.not_to raise_error
    end
  end

  describe "#to_stat" do
    it "exposes counters and timings" do
      worker = described_class.spawn(worker_index: 0, hooks: nil) { |x| x }
      worker.shutdown
      worker.close_pipes
      worker.reap
      worker.items_completed = 7
      worker.busy_time = 1.5
      worker.wall_time = 2.0
      stat = worker.to_stat
      expect(stat.pid).to eq(worker.pid)
      expect(stat.items_completed).to eq(7)
      expect(stat.busy_time).to eq(1.5)
      expect(stat.wall_time).to eq(2.0)
    end
  end
end
