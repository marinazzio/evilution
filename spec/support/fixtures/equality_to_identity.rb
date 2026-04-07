# frozen_string_literal: true

class EqualityToIdentityExample
  def simple_equality(a, b)
    a == b
  end

  def equality_with_literal(x)
    x == 0
  end

  def equality_in_condition(a, b)
    if a == b # rubocop:disable Style/GuardClause,Style/IfUnlessModifier
      "same"
    end
  end

  def string_equality(name)
    name == "admin"
  end

  def not_equal(a, b)
    a != b
  end

  def greater_than(a, b)
    a > b
  end
end
