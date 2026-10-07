# frozen_string_literal: true

$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))
require "test-unit"
require "calc"

# `double` is covered by a passing test. `triple` is covered only by a test
# that fails whatever the code does, and `half` by nothing.
class CalcTest < Test::Unit::TestCase
  def test_doubles
    assert_equal 8, Calc.new.double(4)
  end

  def test_triples_according_to_a_test_that_was_never_right
    assert_equal 7, Calc.new.triple(2)
  end
end
