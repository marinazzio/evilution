# frozen_string_literal: true

class CaseInExample
  def two_clauses(x)
    case x
    in Integer
      :int
    in String
      :str
    end
  end

  def with_else(x)
    case x
    in Integer
      :int
    in String
      :str
    else
      :other
    end
  end

  def single_clause(x)
    case x
    in Integer
      :int
    end
  end

  def guarded_clause(x)
    case x
    in [1, *rest] if rest.any?
      rest
    in Array
      :array
    end
  end

  def then_form(x)
    case x
    in Integer then :int
    in String then :str
    end
  end

  def empty_body_clause(x)
    case x
    in Integer
    in String
      :str
    end
  end

  def destructuring(x)
    case x
    in {name: String => name, age: Integer}
      name
    in [first, *]
      first
    end
  end

  def nested(x, y)
    case x
    in Integer
      case y
      in Symbol
        :sym
      in Float
        :float
      end
    in String
      :str
    end
  end

  def empty_else(x)
    case x
    in Integer
      :int
    else
    end
  end

  def multi_statement_else(x)
    case x
    in Integer
      :int
    else
      log(x)
      :other
    end
  end

  def single_clause_with_else(x)
    case x
    in Integer
      :int
    else
      :other
    end
  end

  def log(value) = value
end
