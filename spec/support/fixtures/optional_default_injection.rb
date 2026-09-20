# frozen_string_literal: true

# Fixture for Mutator::Operator::OptionalDefaultInjection specs.
class OptionalDefaultInjectionTarget
  def single_optional(value = 1)
    touch(value)
  end

  def multi_statement(value = 1)
    prepare
    touch(value)
  end

  def two_optionals(first = 1, second = 2)
    touch(first, second)
  end

  def computed_default(value = compute)
    touch(value)
  end

  def default_from_earlier_parameter(first, second = first * 2)
    touch(second)
  end

  def with_rescue(value = 1)
    touch(value)
  rescue StandardError
    nil
  end

  def with_ensure(value = 1)
    touch(value)
  ensure
    cleanup
  end

  def shadowed_by_block_param(value = 1)
    [1, 2].each { |value| touch(value) }
  end

  def read_in_rescue(value = 1)
    prepare
  rescue StandardError
    touch(value)
  end

  def read_inside_block(value = 1)
    [1, 2].each { |i| touch(value, i) }
  end

  def self.singleton_optional(value = 1)
    touch(value)
  end

  def unused_optional(value = 1)
    touch
  end

  def underscore_optional(_value = 1)
    touch
  end

  def underscore_read(_value = 1)
    touch(_value)
  end

  def endless_optional(value = 1) = touch(value)

  def empty_body(value = 1); end

  def rescue_only(value = 1)
  rescue StandardError
    touch(value)
  end

  def only_required(value)
    touch(value)
  end

  def only_keyword(key: 1)
    touch(key)
  end

  def no_params
    touch
  end

  def block_with_optional(items)
    items.each { |i, extra = 1| touch(i, extra) }
  end

  def compute
    1
  end

  def prepare
    nil
  end

  def cleanup
    nil
  end

  def touch(*args)
    args
  end
end
