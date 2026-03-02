class NegationExample
  def check_empty(list)
    list.empty?
  end

  def check_nil(value)
    value.nil?
  end

  def check_include(list, item)
    list.include?(item)
  end

  def check_non_predicate(value)
    value.to_s
  end
end
