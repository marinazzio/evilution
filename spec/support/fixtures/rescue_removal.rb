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

  # EV-kws8 (#1205) case 1: orphan `else` after stripping the sole rescue.
  # The else attaches to the rescue chain; removing the only rescue leaves
  # `def ... else ... end` which is a syntax error.
  def rescue_with_else
    dangerous_call
  rescue Errno::ENOENT
    abort
  else
    succeed
  end

  # Variant: rescue+else within a begin/ensure block — removing the sole
  # rescue must also drop the else even though ensure stays.
  def rescue_with_else_and_ensure
    begin
      dangerous_call
    rescue Errno::ENOENT
      abort
    else
      succeed
    ensure
      cleanup
    end
  end

  # Multi-rescue + else: removing ANY single rescue still leaves another
  # rescue in the chain, so the else remains valid. Both mutations must
  # parse and keep the else.
  def multiple_rescues_with_else
    dangerous_call
  rescue ArgumentError
    handle_arg
  rescue RuntimeError
    handle_runtime
  else
    succeed
  end

  # EV-kws8 case 2 (roda streaming.rb:125, sinatra base.rb:610): RescueNode
  # whose only body is a comment, followed by an ensure clause. Prism's
  # statements field is nil for a comment-only body, so the old end-offset
  # calculation fell short at the `rescue` keyword and left the exception
  # class name (`ClosedQueueError`) orphaned in the source.
  def rescue_comment_only_with_ensure
    begin
      do_work
    rescue ClosedQueueError
      # intentionally swallowed
    ensure
      cleanup
    end
  end
end
