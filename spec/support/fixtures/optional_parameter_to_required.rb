# frozen_string_literal: true

# Fixture for Mutator::Operator::OptionalParameterToRequired specs.
class OptionalParameterToRequiredTarget
  def single_optional(value = 1)
    value
  end

  def leading_required(first, value = 2)
    [first, value]
  end

  def two_optionals(first = 1, second = 2)
    [first, second]
  end

  def with_rest(value = 1, *rest)
    [value, rest]
  end

  def with_keyword(value = 1, key: nil)
    [value, key]
  end

  def with_block(value = 1, &blk)
    [value, blk]
  end

  def complex_default(value = compute)
    value
  end

  def endless_optional(value = 1) = value

  def self.singleton_optional(value = 1)
    value
  end

  def only_required(value)
    value
  end

  def only_keyword(key: 1)
    key
  end

  def no_params
    1
  end

  def block_with_optional(users)
    users.each { |u, extra = 1| touch(u, extra) }
  end

  def lambda_with_optional
    ->(value = 1) { value }
  end

  def compute
    1
  end

  def touch(*args)
    args
  end
end
