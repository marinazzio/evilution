# frozen_string_literal: true

class PatternMatchingAlternative
  def two_alternatives(value)
    case value
    in Integer | Float
      :numeric
    in String
      :string
    end
  end

  def three_alternatives(value)
    case value
    in :foo | :bar | :baz
      :matched
    in Symbol
      :other
    end
  end

  def no_alternatives(value)
    case value
    in Integer
      :integer
    in String
      :string
    end
  end

  def complex_alternatives(value)
    case value
    in { name: String } | { name: Symbol }
      :named
    in Hash
      :other
    end
  end
end
