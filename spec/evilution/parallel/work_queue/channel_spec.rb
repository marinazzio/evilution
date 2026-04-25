# frozen_string_literal: true

require "spec_helper"
require "evilution/parallel/work_queue/channel"
require "evilution/parallel/work_queue/channel/frame"

RSpec.describe Evilution::Parallel::WorkQueue::Channel do
  describe ".write + .read round-trip" do
    it "returns the original object" do
      r, w = IO.pipe
      [r, w].each(&:binmode)
      described_class.write(w, [:idx, :ok, "result"])
      w.close
      expect(described_class.read(r)).to eq([:idx, :ok, "result"])
    end

    it "supports multiple frames in sequence" do
      r, w = IO.pipe
      [r, w].each(&:binmode)
      described_class.write(w, :first)
      described_class.write(w, :second)
      w.close
      expect(described_class.read(r)).to eq(:first)
      expect(described_class.read(r)).to eq(:second)
    end
  end

  describe ".read" do
    it "returns nil on EOF" do
      r, w = IO.pipe
      [r, w].each(&:binmode)
      w.close
      expect(described_class.read(r)).to be_nil
    end

    it "returns nil on truncated payload" do
      r, w = IO.pipe
      [r, w].each(&:binmode)
      payload = Marshal.dump(:big_string)
      w.write([payload.bytesize + 100].pack("N") + payload)
      w.close
      expect(described_class.read(r)).to be_nil
    end
  end
end
