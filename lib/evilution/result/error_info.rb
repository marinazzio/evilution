# frozen_string_literal: true

require_relative "../result"

class Evilution::Result::ErrorInfo
  attr_reader :message, :klass, :backtrace

  def self.from_fields(message: nil, klass: nil, backtrace: nil)
    return nil if message.nil? && klass.nil? && backtrace.nil?

    new(message: message, klass: klass, backtrace: backtrace)
  end

  def initialize(message: nil, klass: nil, backtrace: nil)
    @message = message
    @klass = klass
    @backtrace = backtrace.nil? ? nil : backtrace.dup.freeze
    freeze
  end
end
