# frozen_string_literal: true

require "spec_helper"
require "timeout"
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

    it "returns nil when the stream ends inside the header" do
      r, w = IO.pipe
      [r, w].each(&:binmode)
      w.write("ab")
      w.close
      expect(described_class.read(r)).to be_nil
    end

    it "reads a frame larger than the pipe holds at once" do
      r, w = IO.pipe
      [r, w].each(&:binmode)
      big = "x" * 300_000
      writer = Thread.new do
        described_class.write(w, big)
        w.close
      end

      expect(described_class.read(r)).to eq(big)
      writer.join
    end

    it "returns nil when the stream ends one byte short of a header" do
      r, w = IO.pipe
      [r, w].each(&:binmode)
      w.write("abc")
      w.close
      expect(described_class.read(r)).to be_nil
    end

    # A frame need not arrive in one piece. What has arrived is kept, the rest
    # is waited for, and no byte of the frame after it is taken with it.
    describe "a frame that arrives in pieces" do
      def frame(object)
        Evilution::Parallel::WorkQueue::Channel::Frame.encode(object)
      end

      def read_while_writing(pieces, pause: 0.1)
        r, w = IO.pipe
        [r, w].each(&:binmode)
        writer = Thread.new do
          pieces.each_with_index do |piece, i|
            sleep pause unless i.zero?
            w.write(piece)
          end
          w.close
        end
        frames = []
        Timeout.timeout(5) do
          while (object = described_class.read(r, frame_timeout: 2))
            frames << object
          end
        end
        writer.join
        frames
      end

      it "waits for a payload that follows its header after a pause" do
        bytes = frame([0, :ok, "late payload"])

        expect(read_while_writing([bytes[0, 4], bytes[4..]])).to eq([[0, :ok, "late payload"]])
      end

      it "puts together a header that arrives in two parts" do
        bytes = frame(:split_header)

        expect(read_while_writing([bytes[0, 2], bytes[2..]])).to eq([:split_header])
      end

      it "puts together a payload that arrives in two parts" do
        bytes = frame("p" * 100)

        expect(read_while_writing([bytes[0, 50], bytes[50..]])).to eq(["p" * 100])
      end

      it "leaves the next frame where it is when the rest of a header arrives with it" do
        first = frame(:first)
        second = frame(:second)

        expect(read_while_writing([first[0, 2], first[2..] + second])).to eq(%i[first second])
      end

      it "leaves the next frame where it is when the rest of a payload arrives with it" do
        first = frame("f" * 100)
        second = frame(:second)

        expect(read_while_writing([first[0, 50], first[50..] + second])).to eq(["f" * 100, :second])
      end

      it "reads bytes that are not text" do
        binary = (0..255).map(&:chr).join.b * 4

        expect(read_while_writing([frame(binary)[0, 300], frame(binary)[300..]])).to eq([binary])
      end
    end

    it "raises BadFrame for a payload that is not a marshal dump" do
      r, w = IO.pipe
      [r, w].each(&:binmode)
      w.write("#{[7].pack("N")}garbage")

      expect { described_class.read(r) }.to raise_error(Evilution::Parallel::WorkQueue::Channel::BadFrame)
    ensure
      w.close
    end

    # The reader is the parent of the pool, and the deadline that would rescue
    # a stuck worker is checked by that same parent. A read that waits for
    # bytes that never come would hang the run with nobody left to notice.
    describe "a frame that never completes while the pipe stays open" do
      it "gives up on a header that announced more than arrives" do
        r, w = IO.pipe
        [r, w].each(&:binmode)
        w.write("#{[1_000_000].pack("N")}abc")

        expect { Timeout.timeout(5) { described_class.read(r, frame_timeout: 0.2) } }
          .to raise_error(Evilution::Parallel::WorkQueue::Channel::BadFrame, "frame cut short: 3 of 1000000 bytes arrived within 0.2s")
      ensure
        w.close
      end

      it "gives up on a header that stops half way" do
        r, w = IO.pipe
        [r, w].each(&:binmode)
        w.write("ab")

        expect { Timeout.timeout(5) { described_class.read(r, frame_timeout: 0.2) } }
          .to raise_error(Evilution::Parallel::WorkQueue::Channel::BadFrame, "frame cut short: 2 of 4 bytes arrived within 0.2s")
      ensure
        w.close
      end

      it "gives up only once the time allowed has passed" do
        r, w = IO.pipe
        [r, w].each(&:binmode)
        w.write("ab")
        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)

        expect { Timeout.timeout(5) { described_class.read(r, frame_timeout: 0.3) } }.to raise_error(Evilution::Parallel::WorkQueue::Channel::BadFrame)

        expect(Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).to be_between(0.3, 2)
      ensure
        w.close
      end

      # The time allowed is for the whole of a read, not for each pause in
      # it: bytes that keep trickling in must not keep the reader for ever.
      it "counts the time from the start of the read, not from the last byte" do
        r, w = IO.pipe
        [r, w].each(&:binmode)
        writer = Thread.new do
          3.times do
            w.write("a")
            sleep 0.2
          end
        end

        expect { Timeout.timeout(5) { described_class.read(r, frame_timeout: 0.3) } }
          .to raise_error(Evilution::Parallel::WorkQueue::Channel::BadFrame, /\Aframe cut short: \d of 4 bytes arrived within 0.3s\z/)
      ensure
        writer.join
        w.close
      end

      # One allowance for the frame, not one for its header and another for
      # its payload: the reader is the one process that could notice a hang.
      it "allows the time once for header and payload together" do
        r, w = IO.pipe
        [r, w].each(&:binmode)
        header = [1_000].pack("N")
        writer = Thread.new do
          w.write(header[0, 2])
          sleep 0.3
          w.write(header[2, 2])
        end
        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)

        expect { Timeout.timeout(5) { described_class.read(r, frame_timeout: 0.4) } }
          .to raise_error(Evilution::Parallel::WorkQueue::Channel::BadFrame, "frame cut short: 0 of 1000 bytes arrived within 0.4s")

        expect(Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).to be_between(0.4, 0.6)
      ensure
        writer.join
        w.close
      end

      it "allows ten seconds unless told otherwise" do
        expect(described_class::FRAME_TIMEOUT).to eq(10)
      end

      it "waits for the first byte of a frame without a limit" do
        r, w = IO.pipe
        [r, w].each(&:binmode)
        writer = Thread.new do
          sleep 0.4
          described_class.write(w, :late)
        end

        expect(described_class.read(r, frame_timeout: 0.1)).to eq(:late)
        writer.join
      ensure
        w.close
      end
    end
  end
end
