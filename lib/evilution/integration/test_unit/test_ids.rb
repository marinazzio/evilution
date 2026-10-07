# frozen_string_literal: true

require_relative "../test_unit"

# Names a Test::Unit test the same way in the baseline and in a mutation run:
# the name the framework gives it, `test_adds(CalcTest)`.
module Evilution::Integration::TestUnit::TestIds
  # Only failures and errors fail a run; pendings, omissions and notifications
  # are faults too, and are left out.
  def self.faults(result)
    result.failures + result.errors
  end

  # The ids of the tests that failed or raised in a finished run.
  def self.failed(result)
    faults(result).map(&:test_name)
  end
end
