class ReceiverConstructorSwapTarget
  def date(value)
    Date.parse(value)
  end

  def date_time(value)
    DateTime.parse(value)
  end

  def time(value)
    Time.parse(value)
  end

  def top_level(value)
    ::Date.parse(value)
  end

  def other_receiver(value)
    JSON.parse(value)
  end

  def variable_receiver(klass, value)
    klass.parse(value)
  end

  def other_selector(value)
    Date.today(value)
  end
end
