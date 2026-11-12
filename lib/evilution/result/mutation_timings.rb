# frozen_string_literal: true

require_relative "../result"

# Where one mutation's time went, in seconds:
#
# - apply:        parsing and evaluating the mutated source
# - test_run:     the first test run against it
# - confirmation: the re-run of a survivor against its whole spec files
# - queue_wait:   in a parallel run, the time from its batch being handed to the
#                 pool to a worker picking it up
#
# A phase that did not happen is nil. What the mutation's duration holds beyond
# these is the cost of the isolation around it: fork, sandbox, reap.
class Evilution::Result::MutationTimings
  PHASES = %i[apply test_run confirmation queue_wait].freeze

  attr_reader(*PHASES)

  # The timings a test process sent back, which may be missing or not a Hash at
  # all when the mutation broke what produced them.
  def self.from_h(hash)
    return nil unless hash.is_a?(Hash)

    fields = PHASES.to_h { |phase| [phase, hash[phase]] }.select { |_, value| value.is_a?(Numeric) }
    return nil if fields.empty?

    new(**fields)
  end

  def initialize(apply: nil, test_run: nil, confirmation: nil, queue_wait: nil)
    @apply = apply
    @test_run = test_run
    @confirmation = confirmation
    @queue_wait = queue_wait
    freeze
  end

  def with_queue_wait(seconds)
    self.class.new(**to_h, queue_wait: seconds)
  end

  def to_h
    PHASES.to_h { |phase| [phase, public_send(phase)] }.compact
  end
end
