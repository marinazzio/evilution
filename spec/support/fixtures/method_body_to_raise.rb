# frozen_string_literal: true

# Fixture for Mutator::Operator::MethodBodyToRaise specs.
class MethodBodyToRaiseTarget
  def single_statement(value)
    value * 2
  end

  def multi_statement(items)
    first = items.first
    items.delete(first)
    first
  end

  def endless_method(value) = value + 1

  def empty_method(value); end

  def bare_raise
    raise
  end

  def raise_with_class
    raise NotImplementedError
  end

  def raise_with_arguments(message)
    raise ArgumentError, message
  end

  def with_rescue(value)
    risky(value)
  rescue StandardError
    nil
  end

  def with_ensure(value)
    risky(value)
  ensure
    cleanup
  end

  def rescue_only
  rescue StandardError
    nil
  end

  def self.singleton(value)
    value.to_s
  end

  private

  def risky(value)
    value
  end

  def cleanup
    nil
  end
end
