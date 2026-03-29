class RescueExample
  def single_rescue
    dangerous_call
  rescue ArgumentError
    handle_error
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

  def rescue_with_body
    setup
    dangerous_call
  rescue StandardError => e
    log(e)
    fallback
  end
end
