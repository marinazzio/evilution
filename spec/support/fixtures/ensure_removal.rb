class EnsureExample
  def simple_ensure
    dangerous_call
  ensure
    cleanup
  end

  def ensure_with_multi_line_body
    dangerous_call
  ensure
    close_connection
    release_lock
  end

  def ensure_with_rescue
    dangerous_call
  rescue StandardError
    handle_error
  ensure
    cleanup
  end

  def no_ensure
    safe_call
  end

  def ensure_without_body
    dangerous_call
  ensure
  end
end
