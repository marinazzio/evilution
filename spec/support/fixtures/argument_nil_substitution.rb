# frozen_string_literal: true

class ArgumentNilSubstitutionFixture
  def single_arg(x)
    transform(x)
  end

  def two_args(a, b)
    obj.compute(a, b)
  end

  def three_args(a, b, c)
    process(a, b, c)
  end

  def no_args
    reset
  end

  def with_receiver(locale)
    I18n.with_locale(locale)
  end

  def with_splat(*)
    forward(*)
  end

  def with_kwargs(a)
    configure(key: a)
  end

  def with_block_arg(&)
    run(&)
  end

  def string_arg
    puts("hello")
  end

  def nested_calls(a, b)
    foo(bar(a), b)
  end
end
