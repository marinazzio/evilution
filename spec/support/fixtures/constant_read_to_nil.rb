class ConstantReadToNilTarget
  def bare_constant
    LIMIT
  end

  def constant_path
    Config::LIMIT
  end

  def nested_constant_path
    App::Config::LIMIT
  end

  def top_level_path
    ::LIMIT
  end

  def assigned
    limit = DEFAULT_LIMIT
    limit
  end

  def as_argument(value)
    value.is_a?(String)
  end

  def as_operand(count)
    count == MAX
  end

  def in_condition(count)
    count > MAX ? MAX : count
  end

  def in_array
    [FIRST, SECOND]
  end

  def in_when(value)
    case value
    when Integer then 1
    else 2
    end
  end

  def path_on_expression
    self.class::LIMIT
  end

  def path_on_call(name)
    resolve(SCOPE, name)::LIMIT
  end

  def call_receiver
    Builder.new
  end

  def path_call_receiver
    Reports::Builder.new
  end

  def chained_call_receiver(name)
    Registry.fetch(name).build
  end

  def void_statement(value)
    LIMIT
    value
  end

  def rescue_class
    run
  rescue ArgumentError, Errors::Timeout
    retry_later
  end

  def rescue_body
    run
  rescue ArgumentError
    FALLBACK
  end

  def no_constants(value)
    value + 1
  end
end
