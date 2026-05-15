class ArgumentMethodCallReplacementExample
  def call_arg
    log(parsed.from_id)
  end

  def hash_value
    log({ from_id: parsed.from_id }.to_json)
  end

  def array_element
    log([parsed.from_id, other.name])
  end

  def chained_call
    log(a.b.c)
  end

  def call_with_block
    log(parsed.attrs { |x| x })
  end

  def no_receiver_arg
    log(local_var)
  end

  def nested_in_kwarg
    log(payload: parsed.from_id)
  end

  def no_args_call
    log
  end
end
