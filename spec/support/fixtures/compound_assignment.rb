# frozen_string_literal: true

class CompoundAssignment
  def add_assign(x)
    x += 1
    x
  end

  def sub_assign(x)
    x -= 1
    x
  end

  def mul_assign(x)
    x *= 2
    x
  end

  def div_assign(x)
    x /= 2
    x
  end

  def mod_assign(x)
    x %= 3
    x
  end

  def pow_assign(x)
    x **= 2
    x
  end

  def ivar_add_assign
    @count += 1
  end

  def cvar_add_assign
    @@total += 1 # rubocop:disable Style/ClassVars
  end

  def gvar_add_assign
    $counter += 1 # rubocop:disable Style/GlobalVars
  end

  def no_compound_assignment
    "hello"
  end
end
