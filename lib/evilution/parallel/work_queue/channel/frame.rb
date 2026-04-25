# frozen_string_literal: true

require_relative "../channel"

module Evilution::Parallel::WorkQueue::Channel::Frame
  module_function

  def encode(object)
    payload = Marshal.dump(object)
    [payload.bytesize].pack("N") + payload
  end

  def decode(header, payload)
    return nil if header.nil? || header.bytesize < 4

    length = header.unpack1("N")
    return nil if payload.nil? || payload.bytesize < length

    Marshal.load(payload) # rubocop:disable Security/MarshalLoad
  end
end
