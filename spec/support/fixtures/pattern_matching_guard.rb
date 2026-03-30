# frozen_string_literal: true

class PatternMatchingGuard
  def simple_if_guard(value)
    case value
    in Integer => n if n > 0
      :positive
    in Integer
      :non_positive
    end
  end

  def unless_guard(value)
    case value
    in String unless value.empty?
      :non_empty
    in String
      :empty
    end
  end

  def complex_guard(value)
    case value
    in [a, b] if a < b
      :ascending
    in [a, b]
      :other
    end
  end

  def no_guard(value)
    case value
    in Integer => n
      n * 2
    in String
      value.upcase
    end
  end

  def multiple_guarded_branches(value)
    case value
    in Integer => n if n > 0
      :positive
    in Integer => n if n < 0
      :negative
    in Integer
      :zero
    end
  end
end
