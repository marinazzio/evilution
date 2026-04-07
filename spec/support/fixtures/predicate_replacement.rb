# frozen_string_literal: true

class PredicateReplacementExample
  def simple_predicate(x)
    x.empty?
  end

  def predicate_with_receiver(arr, val)
    arr.include?(val)
  end

  def bare_predicate
    valid?
  end

  def nil_check(x)
    x.nil?
  end

  def predicate_with_block(items)
    items.any? { |i| i > 0 }
  end

  def non_predicate_method(x)
    x.length
  end
end
