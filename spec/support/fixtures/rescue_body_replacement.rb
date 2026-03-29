class RescueBodyExample
  def single_rescue
    dangerous_call
  rescue ArgumentError
    handle_error
  end

  def rescue_with_multi_line_body
    dangerous_call
  rescue StandardError => e
    log(e)
    fallback
  end

  def multiple_rescues
    dangerous_call
  rescue ArgumentError
    handle_arg_error
  rescue RuntimeError
    handle_runtime_error
  end

  def no_rescue
    safe_call
  end

  def rescue_with_raise
    dangerous_call
  rescue StandardError
    raise
  end

  def empty_rescue
    dangerous_call
  rescue StandardError
  end
end
