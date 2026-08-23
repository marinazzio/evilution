# frozen_string_literal: true

class PatternPredicateExample
  def as_if_predicate(x)
    if x in Integer
      :yes
    else
      :no
    end
  end

  def as_value(x)
    flag = (x in Integer)
    flag
  end

  # `flag = x in Integer` parses as `(flag = x) in Integer`, so the predicate
  # node covers the assignment too.
  def unparenthesised_value(x)
    flag = x in Integer
    flag
  end

  def as_return(x)
    return (x in Integer)
  end

  def in_block(items)
    items.select { |item| item in String }
  end

  def with_binding(x)
    if x in {name: String => name}
      name
    end
  end

  def destructuring(x)
    x in [Integer => first, *rest]
  end

  def combined(x, flag)
    (x in Integer) && flag
  end

  def two_predicates(x, y)
    (x in Integer) || (y in String)
  end

  # An outer predicate whose value expression contains another predicate: the
  # inner one is only reachable by recursing past the outer.
  def nested_predicates(items)
    items.map { |i| i in String } in [true, *]
  end

  def required_match(x)
    x => Integer
    x
  end

  def no_pattern(x)
    x.is_a?(Integer)
  end
end
