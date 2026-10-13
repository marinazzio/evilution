# frozen_string_literal: true

require_relative "../channel"

module Evilution::Parallel::WorkQueue::Channel::Frame
  module_function

  def encode(object)
    payload = Marshal.dump(object)
    [payload.bytesize].pack("N") + payload
  end

  # Marshal.load is safe here: payload originates from a sibling worker the
  # parent itself forked, transferred over a private pipe inside our process
  # tree. No external/untrusted input ever reaches this code. See
  # .rubocop.yml (Security/MarshalLoad) for the full rationale.
  #
  # Trusted is not the same as well-formed: a process the worker forked holds
  # the pipe too. A frame of the announced length that does not load is a
  # BadFrame; one shorter than announced is the end of the stream, nil.
  def decode(header, payload)
    return nil if header.nil? || header.bytesize < 4

    length = header.unpack1("N")
    return nil if payload.nil? || payload.bytesize < length

    Marshal.load(payload)
  rescue TypeError, ArgumentError => e
    raise Evilution::Parallel::WorkQueue::Channel::BadFrame, "#{e.class}: #{e.message.gsub(/\s+/, " ")}"
  end
end
