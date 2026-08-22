class IfBranchSwapTarget
  def pick(c, x, y)
    if c
      x
    else
      y
    end
  end

  def multi_statement_else(c, x, y)
    if c
      x
    else
      log(y)
      y
    end
  end

  def elsif_chain(a, b, x, y, z)
    if a
      x
    elsif b
      y
    else
      z
    end
  end

  def no_else(c, x)
    if c
      x
    end
  end

  def empty_then(c, y)
    if c
    else
      y
    end
  end

  def empty_else(c, x)
    if c
      x
    else
    end
  end

  def ternary(c, x, y)
    c ? x : y
  end

  def nested(c, d, x, y, z)
    if c
      x
    else
      if d
        y
      else
        z
      end
    end
  end

  def log(value) = value
end
