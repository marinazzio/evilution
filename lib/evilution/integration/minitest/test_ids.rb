# frozen_string_literal: true

require_relative "../minitest"

# Names a Minitest test the same way in the baseline and in a mutation run:
# its class and its method, `CalcTest#test_adds`.
#
# A test class without a name has only its method to go by, so two such
# classes with a method of the same name are told apart by neither run.
module Evilution::Integration::Minitest::TestIds
  def self.of(result)
    class_name = result.respond_to?(:class_name) ? result.class_name : result.class.name
    "#{class_name}##{result.name}"
  end

  # The ids of the tests that failed, from the summary reporter of the run.
  # It keeps every result that did not pass, skips included.
  def self.failed(summary)
    summary.results.reject(&:skipped?).map { |result| of(result) }
  end
end
