# frozen_string_literal: true

require_relative "../work_queue"

module Evilution::Parallel::WorkQueue::Channel
  module_function

  def write(io, object)
    io.write(Frame.encode(object))
    io.flush
  end

  def read(io)
    header = io.read(4)
    return nil if header.nil? || header.bytesize < 4

    length = header.unpack1("N")
    payload = io.read(length)
    Frame.decode(header, payload)
  end
end

require_relative "channel/frame"
