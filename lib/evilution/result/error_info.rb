# frozen_string_literal: true

require_relative "../result"

class Evilution::Result::ErrorInfo
  attr_reader :message, :klass, :backtrace

  def initialize(message: nil, klass: nil, backtrace: nil)
    @message = message
    @klass = klass
    @backtrace = backtrace.nil? ? nil : backtrace.dup.freeze
    freeze
  end
end
