# frozen_string_literal: true

require_relative "../integration"

# The tests the baseline saw failing before any mutation ran, by the ids the
# integration gives them.
#
# Such a test fails whatever the mutation is, so a mutation run in which
# nothing else failed has no verdict. The question is asked in the process
# that ran the tests: the names of everything that failed need not travel
# back, only the answer.
class Evilution::Integration::KnownFailures
  def initialize(ids)
    @ids = ids.to_set
  end

  def empty?
    @ids.empty?
  end

  # Whether failed_ids names at least one test, and none the baseline did not
  # already see failing.
  def only?(failed_ids)
    !failed_ids.empty? && failed_ids.all? { |id| @ids.include?(id) }
  end
end
