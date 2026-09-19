# frozen_string_literal: true

# Fixture for Mutator::Operator::TypedDefaultReturn specs.
class TypedDefaultReturnTarget
  def mapped(users)
    users.map(&:name)
  end

  def selected(users)
    users.select(&:active?)
  end

  def hashed(users)
    users.to_h { |u| [u.id, u] }
  end

  def counted(users)
    users.count
  end

  def joined(users)
    users.map(&:name).join(", ")
  end

  def interpolated(name)
    "hi #{name}"
  end

  def endless_mapped(users) = users.map(&:name)

  def with_rescue(users)
    users.map(&:name)
  rescue StandardError
    []
  end

  def literal_array
    %w[a b]
  end

  def literal_hash
    { a: 1 }
  end

  def literal_string
    "fixed"
  end

  def literal_integer
    42
  end

  def literal_float
    4.2
  end

  def unknown_selector(users)
    users.summarise
  end

  def instance_variable_body
    @name
  end

  def multi_statement(users)
    names = users.map(&:name)
    names.sort
  end

  def multi_statement_leading_call(users)
    users.map(&:name)
    @done = true
  end

  def empty_method(users); end

  def rescue_only
  rescue StandardError
    []
  end
end
