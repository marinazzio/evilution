# frozen_string_literal: true

require_relative "base"

# The same limit for every mutation: the timeout the user gave, or the default
# when nothing better is known. nil runs without a limit.
class Evilution::Runner::MutationExecutor::TimeoutPolicy::Fixed < Evilution::Runner::MutationExecutor::TimeoutPolicy::Base
  def initialize(seconds)
    super()
    @seconds = seconds
    freeze
  end

  def call(_mutation)
    @seconds
  end
end
