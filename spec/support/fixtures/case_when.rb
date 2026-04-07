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
end
