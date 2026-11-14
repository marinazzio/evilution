# frozen_string_literal: true

require_relative "../mutation_executor"

# The tests that killed mutations earlier in this run, kept in the parent so
# each mutation can be sent out with the tests most likely to kill it: those
# that killed a mutation on its own line, then those that killed one elsewhere
# in its subject. The latest killer of each comes first.
#
# Only the order of a mutation's tests comes of it, never which tests run, so
# a killer that has gone stale costs one test run at the most.
class Evilution::Runner::MutationExecutor::KillHistory
  LIMIT = 16
  EMPTY = [].freeze
  private_constant :EMPTY

  # Remembers nothing: for a run, or a test, that does without.
  class None
    def record(_mutation, status:, killing_test:); end

    def killers_for(_mutation)
      EMPTY
    end
  end
  private_constant :None

  NONE = None.new.freeze

  def initialize
    @by_line = {}
    @by_subject = {}
  end

  def record(mutation, status:, killing_test:)
    return unless status == :killed && killing_test

    remember(@by_line, line_key(mutation), killing_test)
    subject = subject_key(mutation)
    remember(@by_subject, subject, killing_test) if subject
  end

  def killers_for(mutation)
    line = @by_line.fetch(line_key(mutation), EMPTY)
    subject = subject_key(mutation)
    nearby = subject ? @by_subject.fetch(subject, EMPTY) : EMPTY
    (line + nearby).uniq.first(LIMIT)
  end

  private

  def remember(index, key, test)
    killers = (index[key] ||= [])
    killers.delete(test)
    killers.unshift(test)
    killers.pop while killers.length > LIMIT
  end

  def line_key(mutation)
    [mutation.file_path, mutation.line]
  end

  def subject_key(mutation)
    subject = mutation.subject
    subject ? [mutation.file_path, subject.name] : nil
  end
end
