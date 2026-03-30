# frozen_string_literal: true

class PatternMatchingArray
  def typed_array(value)
    case value
    in [Integer, String, Symbol]
      :typed_triple
    in Array
      :other
    end
  end

  def array_with_rest(value)
    case value
    in [1, 2, *rest]
      rest
    in Array
      :other
    end
  end

  def find_pattern(value)
    case value
    in [*, Integer => mid, *]
      mid
    in Array
      :not_found
    end
  end

  def single_element_array(value)
    case value
    in [Integer]
      :single
    in Array
      :other
    end
  end

  def array_with_posts(value)
    case value
    in [*rest, Integer, String]
      :ends_with
    in Array
      :other
    end
  end

  def no_array_pattern(value)
    case value
    in Integer
      :number
    in String
      :string
    end
  end

  def find_pattern_multiple(value)
    case value
    in [*, Integer => a, String => b, *]
      [a, b]
    in Array
      :not_found
    end
  end
end
