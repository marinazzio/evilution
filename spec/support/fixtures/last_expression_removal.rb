class LastExpressionRemovalExample
  def predicate_true?
    log_something
    true
  end

  def predicate_false?
    do_work
    false
  end

  def trailing_nil
    side_effect
    nil
  end

  def trailing_integer
    helper
    42
  end

  def trailing_symbol
    work
    :ok
  end

  def single_literal?
    true
  end

  def no_trailing_literal
    helper
    helper.other
  end

  def empty
  end

  def trailing_call
    do_work
    helper.thing
  end

  def nested_outer
    setup
    def nested_inner
      side_effect
      true
    end
  end

  def rescue_bodied
    do_work
  rescue StandardError
    log
  end
end
