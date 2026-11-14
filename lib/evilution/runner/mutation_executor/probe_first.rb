# frozen_string_literal: true

require_relative "../mutation_executor"

# Which subjects no selected test exercises, learnt from one sentinel mutation
# per subject that runs before the others: the method's whole body replaced by
# a bare `raise`. When even that survives, no test calls the method on a path
# it checks, and the subject's other mutations would almost all survive too;
# they are reported as survivors implied by the sentinel, without a run.
#
# The sentinel is the body raise of the subject's own method, the one reported
# at the subject's line; a method nested inside has its own line and is just
# another mutation of the subject. A subject without a sentinel (an empty
# body, a body that already only raises, a subject that is not a method) is
# never skipped.
class Evilution::Runner::MutationExecutor::ProbeFirst
  SENTINEL_OPERATOR = "method_body_to_raise"
  # A sentinel no test executes says the same as one that ran and survived.
  UNEXERCISED_STATUSES = %i[survived uncovered].freeze
  private_constant :UNEXERCISED_STATUSES

  # Probes nothing: for a run without probe-first.
  class None
    def sentinel?(_mutation)
      false
    end

    def record(_result); end

    def implied_by(_mutation)
      nil
    end
  end
  private_constant :None

  NONE = None.new.freeze

  def initialize
    @unexercised = Set.new
  end

  def sentinel?(mutation)
    subject = mutation.subject
    return false if subject.nil?

    mutation.operator_name == SENTINEL_OPERATOR && mutation.line == subject.line_number
  end

  # The sentinels go first, so every one of them has a verdict before any
  # other mutation is looked at.
  def split(mutations)
    mutations.partition { |mutation| sentinel?(mutation) }
  end

  def record(result)
    mutation = result.mutation
    return unless sentinel?(mutation)
    return unless UNEXERCISED_STATUSES.include?(result.status)

    @unexercised << key(mutation)
  end

  # The operator of the sentinel that implies the mutation survives, or nil
  # when the mutation has to run.
  def implied_by(mutation)
    return nil if mutation.subject.nil? || sentinel?(mutation)

    @unexercised.include?(key(mutation)) ? SENTINEL_OPERATOR : nil
  end

  private

  # The line tells apart two methods of one name in a file, such as a
  # method defined again where its class is reopened.
  def key(mutation)
    subject = mutation.subject
    [mutation.file_path, subject.name, subject.line_number]
  end
end
