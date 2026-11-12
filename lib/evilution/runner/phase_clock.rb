# frozen_string_literal: true

require_relative "../runner"

# Wall time of each phase of a run, in the order the phases ran. A phase
# measured more than once adds up.
class Evilution::Runner::PhaseClock
  def initialize
    @phases = {}
  end

  def measure(phase)
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    yield
  ensure
    @phases[phase] = @phases.fetch(phase, 0.0) + (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started)
  end

  def to_h
    @phases.dup.freeze
  end
end
