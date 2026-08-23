# frozen_string_literal: true

class CaseWhenExample
  def simple_case(x)
    case x
    when 1
      "one"
    when 2
      "two"
    else
      "other"
    end
  end

  def case_without_else(x)
    case x
    when :a
      "alpha"
    when :b
      "beta"
    end
  end

  def single_when(x)
    case x
    when true
      "yes"
    end
  end

  def case_with_multiline_body(x)
    case x
    when 1
      setup
      process
      cleanup
    when 2
      "quick"
    end
  end

  def case_with_empty_when(x)
    case x
    when 1
      # intentionally empty
    when 2
      "two"
    end
  end

  def empty_when_with_then(x)
    case x
    when 1 then
    when 2
      "two"
    end
  end

  def empty_when_multiple_conditions(x)
    case x
    when 1, 2
      # intentionally empty
    else
      "other"
    end
  end

  def empty_when_after_body(x)
    case x
    when 1
      "one"
    when 2
      # intentionally empty
    end
  end

  def only_empty_when(x)
    case x
    when 1
      # intentionally empty
    end
  end

  def two_conditions(x)
    case x
    when 1, 2
      "low"
    when 3
      "high"
    end
  end

  def single_condition_arm_first(x)
    case x
    when 1
      "one"
    when 2, 3
      "pair"
    end
  end

  def three_conditions(x)
    case x
    when :a, :b, :c
      "letter"
    end
  end

  def conditions_with_then(x)
    case x
    when 1, 2 then "low"
    end
  end

  def conditions_with_splat(x, rest)
    case x
    when 1, *rest
      "matched"
    end
  end

  def conditions_across_lines(x)
    case x
    when 1,
         2
      "low"
    end
  end
end
