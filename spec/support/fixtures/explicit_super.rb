# frozen_string_literal: true

# rubocop:disable Style/SuperArguments
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

  def with_splat_and_block(*extensions, &block)
    super(*extensions, &block)
  end

  def with_args_and_block(a, b, &block)
    super(a, b, &block)
  end

  def with_splat_only(*x)
    super(*x)
  end
end
# rubocop:enable Style/SuperArguments
