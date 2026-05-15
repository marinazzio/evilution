class MethodBodyExample
  def with_body
    42
  end

  def with_complex_body
    x = 1
    y = 2
    x + y
  end

  def empty_method
  end

  def with_super_in_body
    super
    42
  end

  def with_forwarding_super(...)
    super(...)
  end

  def with_method_rescue
    do_work
  rescue StandardError => e
    handle(e)
  end

  def with_super_and_method_rescue(arg)
    super(arg)
  rescue StandardError => e
    recover(e)
  end

  def with_method_ensure
    do_work
  ensure
    cleanup
  end

  def only_rescue_no_body
  rescue StandardError => e
    handle(e)
  end
end
