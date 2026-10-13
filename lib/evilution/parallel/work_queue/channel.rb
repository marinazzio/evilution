# frozen_string_literal: true

require "io/wait"
require_relative "../work_queue"

module Evilution::Parallel::WorkQueue::Channel
  # A frame that arrived but is not one the peer wrote: bytes that do not
  # decode, or a frame that stops before the length its header announced.
  #
  # The pipes of the pool are inherited by the processes a worker forks, so
  # the code under test can write into them. After such a frame the stream is
  # out of step and nothing read from it later can be trusted; the reader
  # gives the peer up. The end of the stream is not this: it reads as nil.
  class BadFrame < StandardError; end

  # Seconds a frame may take to arrive once its first byte has. A writer
  # sends a frame in one call, so the rest follows at once; a header that
  # announces bytes nobody will send must not hold the reader for ever.
  FRAME_TIMEOUT = 10

  module_function

  def write(io, object)
    io.write(Frame.encode(object))
    io.flush
  end

  # Waits for a frame without a limit, since an idle peer is no fault, and
  # for the rest of one that has begun no longer than `frame_timeout`.
  def read(io, frame_timeout: FRAME_TIMEOUT)
    io.wait_readable
    header = read_exactly(io, 4, frame_timeout)
    return nil if header.bytesize < 4

    payload = read_exactly(io, header.unpack1("N"), frame_timeout)
    Frame.decode(header, payload)
  end

  # Up to `count` bytes: fewer only when the stream ended first.
  def read_exactly(io, count, frame_timeout)
    deadline = now + frame_timeout
    buffer = String.new

    while buffer.bytesize < count
      chunk = io.read_nonblock(count - buffer.bytesize, exception: false)
      return buffer if chunk.nil?

      if chunk == :wait_readable
        await(io, deadline, buffer.bytesize, count, frame_timeout)
      else
        buffer << chunk
      end
    end
    buffer
  end

  def await(io, deadline, arrived, count, frame_timeout)
    remaining = deadline - now
    return if remaining.positive? && io.wait_readable(remaining)

    raise BadFrame, "frame cut short: #{arrived} of #{count} bytes arrived within #{frame_timeout}s"
  end

  def now
    Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end
end

require_relative "channel/frame"
