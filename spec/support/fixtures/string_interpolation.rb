# frozen_string_literal: false

class StringInterpolationExample
  def simple_interpolation(name)
    "hello #{name}"
  end

  def multiple_interpolations(first, last)
    "#{first} #{last}"
  end

  def method_call_interpolation(user)
    "welcome #{user.name}"
  end

  def expression_interpolation(x)
    "result: #{x + 1}"
  end

  def interpolation_with_surrounding_text(name)
    "Dear #{name}, welcome!"
  end

  def symbol_interpolation(name)
    :"key_#{name}"
  end

  def no_interpolation
    "plain string"
  end

  def empty_interpolation
    "#{ }" # rubocop:disable Lint/EmptyExpression,Lint/EmptyInterpolation,Style/RedundantInterpolation
  end
end
