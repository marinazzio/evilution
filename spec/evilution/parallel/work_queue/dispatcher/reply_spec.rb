# frozen_string_literal: true

require "spec_helper"
require "evilution/parallel/work_queue/dispatcher"

RSpec.describe Evilution::Parallel::WorkQueue::Dispatcher::Reply do
  let(:bad_frame) { Evilution::Parallel::WorkQueue::Channel::BadFrame }
  let(:worker) { double("Worker", in_flight_indices: [3, 4]) }

  def reply_to(message)
    allow(worker).to receive(:read_result).and_return(message)
    described_class.from(worker)
  end

  describe ".from" do
    it "is the message when it is a result of an item the worker holds" do
      expect(reply_to([3, :ok, "value"])).to eq([3, :ok, "value"])
    end

    it "is the message when it reports an exception for an item the worker holds" do
      error = ArgumentError.new("boom")

      expect(reply_to([4, :error, error])).to eq([4, :error, error])
    end

    it "is nil when the stream has ended" do
      expect(reply_to(nil)).to be_nil
    end

    it "is UNREADABLE when the frame does not decode" do
      allow(worker).to receive(:read_result).and_raise(bad_frame, "garbled")

      expect(described_class.from(worker)).to be(described_class::UNREADABLE)
    end

    # A process the worker forked holds the pipe too, and what it writes may
    # happen to be a marshal dump. Taken at its word, such a frame would move
    # the dispatcher's counters, or be raised as the error of the run.
    {
      "is not an array" => true,
      "is too short" => [3, :ok],
      "is too long" => [3, :ok, 1, 2],
      "names an item the worker does not hold" => [99, :ok, 1],
      "has a status that is not one" => [3, :maybe, 1],
      "has a status that is not one, with an exception for a value" => [3, :maybe, RuntimeError.new("boom")],
      "has no status, with an exception for a value" => [3, nil, RuntimeError.new("boom")],
      "reports an error that is not an exception" => [3, :error, "boom"]
    }.each do |what, message|
      it "is UNREADABLE when the message #{what}" do
        expect(reply_to(message)).to be(described_class::UNREADABLE)
      end
    end

    it "takes an :ok result of any value, nil and false included" do
      expect(reply_to([3, :ok, nil])).to eq([3, :ok, nil])
      expect(reply_to([4, :ok, false])).to eq([4, :ok, false])
    end

    it "lets other errors of the read through" do
      allow(worker).to receive(:read_result).and_raise(IOError, "closed stream")

      expect { described_class.from(worker) }.to raise_error(IOError)
    end
  end

  it "tells an unreadable reply from the end of the stream, which is nil" do
    expect(described_class::UNREADABLE).not_to be_nil
  end
end
