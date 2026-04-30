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
  def decode(header, payload)
    return nil if header.nil? || header.bytesize < 4

    length = header.unpack1("N")
    return nil if payload.nil? || payload.bytesize < length

    Marshal.load(payload)
  end
end
