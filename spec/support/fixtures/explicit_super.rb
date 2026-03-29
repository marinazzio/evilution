# frozen_string_literal: true

# rubocop:disable Lint/UselessMethodDefinition, Style/SuperArguments
class ExplicitSuperExample
  def with_args(a, b)
    super(a, b)
  end

  def with_single_arg(a)
    super(a)
  end

  def with_no_args
    super()
  end

  def no_super
    "plain"
  end
end
# rubocop:enable Lint/UselessMethodDefinition, Style/SuperArguments
