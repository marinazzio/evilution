# frozen_string_literal: true

require "spec_helper"
require "evilution/parallel/work_queue/worker/loop"

RSpec.describe Evilution::Parallel::WorkQueue::Worker::Loop do
  describe ".run" do
    let(:cmd_pair) { IO.pipe.tap { |pair| pair.each(&:binmode) } }
    let(:res_pair) { IO.pipe.tap { |pair| pair.each(&:binmode) } }
    let(:cmd_read)  { cmd_pair[0] }
    let(:cmd_write) { cmd_pair[1] }
    let(:res_read)  { res_pair[0] }
    let(:res_write) { res_pair[1] }

    before do
      # Loop calls exit! at end of ensure — stub to allow test process to continue
      allow(described_class).to receive(:exit!)
    end

    it "processes items and writes :ok results" do
      Evilution::Parallel::WorkQueue::Channel.write(cmd_write, [0, 5])
      Evilution::Parallel::WorkQueue::Channel.write(cmd_write, [1, 10])
      Evilution::Parallel::WorkQueue::Channel.write(cmd_write, Evilution::Parallel::WorkQueue::SHUTDOWN)
      cmd_write.close

      described_class.run(cmd_read, res_write) { |x| x * 2 }

      results = []
      until res_read.eof?
        msg = Evilution::Parallel::WorkQueue::Channel.read(res_read)
        break if msg.nil?

        results << msg
      end

      expect(results[0]).to eq([0, :ok, 10])
      expect(results[1]).to eq([1, :ok, 20])
      stats_msg = results[2]
      expect(stats_msg.first).to eq(Evilution::Parallel::WorkQueue::STATS)
      expect(stats_msg[1]).to be >= 0.0
      expect(stats_msg[2]).to be >= 0.0
    end

    it "captures user-block StandardError as :error result" do
      Evilution::Parallel::WorkQueue::Channel.write(cmd_write, [0, :boom])
      Evilution::Parallel::WorkQueue::Channel.write(cmd_write, Evilution::Parallel::WorkQueue::SHUTDOWN)
      cmd_write.close

      described_class.run(cmd_read, res_write) { |_| raise StandardError, "user error" }

      first = Evilution::Parallel::WorkQueue::Channel.read(res_read)
      expect(first[0]).to eq(0)
      expect(first[1]).to eq(:error)
      expect(first[2]).to be_a(StandardError)
      expect(first[2].message).to eq("user error")
    end

    it "captures Exception (not just StandardError) from user block" do
      Evilution::Parallel::WorkQueue::Channel.write(cmd_write, [0, :boom])
      Evilution::Parallel::WorkQueue::Channel.write(cmd_write, Evilution::Parallel::WorkQueue::SHUTDOWN)
      cmd_write.close

      described_class.run(cmd_read, res_write) { |_| raise SystemStackError, "deep" }

      first = Evilution::Parallel::WorkQueue::Channel.read(res_read)
      expect(first[1]).to eq(:error)
      expect(first[2]).to be_a(SystemStackError)
    end

    it "fires worker_process_start hook when hooks present" do
      hooks = double("hooks")
      expect(hooks).to receive(:fire).with(:worker_process_start)

      Evilution::Parallel::WorkQueue::Channel.write(cmd_write, Evilution::Parallel::WorkQueue::SHUTDOWN)
      cmd_write.close

      described_class.run(cmd_read, res_write, hooks: hooks) { |x| x }
    end

    it "does not fire hook when hooks is nil" do
      Evilution::Parallel::WorkQueue::Channel.write(cmd_write, Evilution::Parallel::WorkQueue::SHUTDOWN)
      cmd_write.close
      expect { described_class.run(cmd_read, res_write, hooks: nil) { |x| x } }.not_to raise_error
    end

    it "treats EOF (nil from Channel) as shutdown" do
      cmd_write.close
      expect { described_class.run(cmd_read, res_write) { |x| x } }.not_to raise_error
    end
  end
end
