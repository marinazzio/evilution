# frozen_string_literal: true

require_relative "../result"

# Where one mutation's time went, in seconds:
#
# - apply:        parsing and evaluating the mutated source
# - test_run:     the first test run against it
# - confirmation: the re-run of a survivor against its whole spec files
# - queue_wait:   in a parallel run, the time from the dispatcher sending it to a
#                 worker to that worker starting it
# - adaptive_timeout: a first run that used up a limit shorter than the fixed
#                 one, after which the mutation was run again under the fixed
#                 limit; the other phases then belong to that second run
#
# A phase that did not happen is nil. What the mutation's duration holds beyond
# these is the cost of the isolation around it: fork, sandbox, reap.
class Evilution::Result::MutationTimings
  PHASES = %i[apply test_run confirmation queue_wait adaptive_timeout].freeze

  attr_reader(*PHASES)

  # The timings a test process sent back, which may be missing or not a Hash at
  # all when the mutation broke what produced them.
  def self.from_h(hash)
    return nil unless hash.is_a?(Hash)

    fields = PHASES.to_h { |phase| [phase, hash[phase]] }.select { |_, value| value.is_a?(Numeric) }
    return nil if fields.empty?

    new(**fields)
  end

  def initialize(apply: nil, test_run: nil, confirmation: nil, queue_wait: nil, adaptive_timeout: nil)
    @apply = apply
    @test_run = test_run
    @confirmation = confirmation
    @queue_wait = queue_wait
    @adaptive_timeout = adaptive_timeout
    freeze
  end

  def with_queue_wait(seconds)
    self.class.new(**to_h, queue_wait: seconds)
  end

  def with_adaptive_timeout(seconds)
    self.class.new(**to_h, adaptive_timeout: seconds)
  end

  def to_h
    PHASES.to_h { |phase| [phase, public_send(phase)] }.compact
  end
end
