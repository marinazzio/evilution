# frozen_string_literal: true

class LambdaBodyExample
  def simple_lambda
    f = -> { 42 }
    f.call
  end

  def lambda_with_args
    f = ->(x) { x + 1 }
    f.call(5)
  end

  def lambda_with_multiline_body
    f = ->(x) do # rubocop:disable Style/Lambda
      y = x * 2
      y + 1
    end
    f.call(3)
  end

  def empty_lambda
    f = -> {}
    f.call
  end

  def multiple_lambdas
    add = ->(a, b) { a + b }
    sub = ->(a, b) { a - b }
    [add, sub]
  end
end
