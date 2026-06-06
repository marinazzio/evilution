# frozen_string_literal: true

require "spec_helper"
require "evilution/parallel/work_queue/worker_registry"

RSpec.describe Evilution::Parallel::WorkQueue::WorkerRegistry do
  around do |example|
    snapshot = described_class.pgids
    snapshot.each { |pgid| described_class.unregister(pgid) }
    example.run
    described_class.pgids.each { |pgid| described_class.unregister(pgid) }
    snapshot.each { |pgid| described_class.register(pgid) }
  end

  describe ".register / .pgids" do
    it "starts empty in an isolated registry" do
      expect(described_class.pgids).to eq([])
    end

    it "records a registered pgid" do
      described_class.register(4242)
      expect(described_class.pgids).to contain_exactly(4242)
    end

    it "records multiple pgids in registration order" do
      described_class.register(10)
      described_class.register(20)
      described_class.register(30)
      expect(described_class.pgids).to eq([10, 20, 30])
    end

    it "exposes pgids as a frozen snapshot" do
      described_class.register(99)
      expect(described_class.pgids).to be_frozen
    end

    it "returns an independent snapshot that does not mutate the registry" do
      described_class.register(1)
      snapshot = described_class.pgids
      described_class.register(2)
      expect(snapshot).to eq([1])
    end
  end

  describe ".unregister" do
    it "removes a registered pgid" do
      described_class.register(7)
      described_class.register(8)
      described_class.unregister(7)
      expect(described_class.pgids).to contain_exactly(8)
    end

    it "is a no-op when the pgid was never registered" do
      described_class.register(5)
      expect { described_class.unregister(999) }.not_to change(described_class, :pgids)
    end

    it "removes every occurrence of a duplicated pgid" do
      described_class.register(3)
      described_class.register(3)
      described_class.unregister(3)
      expect(described_class.pgids).to eq([])
    end
  end

  describe ".signal_all" do
    it "sends the signal to the negated pgid of every registered group" do
      allow(Process).to receive(:kill)
      described_class.register(11)
      described_class.register(22)

      described_class.signal_all("TERM")

      expect(Process).to have_received(:kill).with("TERM", -11)
      expect(Process).to have_received(:kill).with("TERM", -22)
    end

    it "swallows Errno::ESRCH for an already-dead group and continues" do
      allow(Process).to receive(:kill).with("INT", -1).and_raise(Errno::ESRCH)
      allow(Process).to receive(:kill).with("INT", -2)
      described_class.register(1)
      described_class.register(2)

      expect { described_class.signal_all("INT") }.not_to raise_error
      expect(Process).to have_received(:kill).with("INT", -2)
    end

    it "does nothing when no workers are registered" do
      allow(Process).to receive(:kill)
      described_class.signal_all("INT")
      expect(Process).not_to have_received(:kill)
    end
  end
end
