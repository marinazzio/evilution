# frozen_string_literal: true

require "spec_helper"
require "evilution/parallel/work_queue/channel/frame"

RSpec.describe Evilution::Parallel::WorkQueue::Channel::Frame do
  describe ".encode" do
    it "produces length-prefixed Marshal payload" do
      bytes = described_class.encode(:hello)
      length = bytes[0, 4].unpack1("N")
      payload = bytes[4..]
      expect(payload.bytesize).to eq(length)
      expect(Marshal.load(payload)).to eq(:hello) # rubocop:disable Security/MarshalLoad
    end

    it "round-trips arbitrary Ruby objects" do
      original = { foo: [1, 2, "three"], bar: nil }
      bytes = described_class.encode(original)
      header = bytes[0, 4]
      payload = bytes[4..]
      expect(described_class.decode(header, payload)).to eq(original)
    end
  end

  describe ".decode" do
    it "returns nil for nil header" do
      expect(described_class.decode(nil, "payload")).to be_nil
    end

    it "returns nil for short header (less than 4 bytes)" do
      expect(described_class.decode("ab", "payload")).to be_nil
    end

    it "returns nil for short payload" do
      bytes = described_class.encode(:big)
      truncated = bytes[4..-2] # drop last byte of payload
      expect(described_class.decode(bytes[0, 4], truncated)).to be_nil
    end

    it "decodes a valid frame" do
      bytes = described_class.encode([:idx, :ok, 42])
      expect(described_class.decode(bytes[0, 4], bytes[4..])).to eq([:idx, :ok, 42])
    end
  end
end
