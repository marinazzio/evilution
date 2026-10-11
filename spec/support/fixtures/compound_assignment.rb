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

  def bitwise_and_assign(x)
    x &= 0xFF
    x
  end

  def bitwise_or_assign(x)
    x |= 0x01
    x
  end

  def bitwise_xor_assign(x)
    x ^= 0x0F
    x
  end

  def left_shift_assign(x)
    x <<= 2
    x
  end

  def right_shift_assign(x)
    x >>= 2
    x
  end

  def logical_and_assign(x)
    x &&= true
    x
  end

  def logical_or_assign(x)
    x ||= "default"
    x
  end

  def ivar_logical_and_assign
    @flag &&= false
  end

  def ivar_logical_or_assign
    @ivar_logical_or_assign ||= "unknown"
  end

  def cvar_logical_and_assign
    @@flag &&= false # rubocop:disable Style/ClassVars
  end

  def cvar_logical_or_assign
    @@cvar_logical_or_assign ||= "unknown" # rubocop:disable Style/ClassVars
  end

  def gvar_logical_and_assign
    $flag &&= false # rubocop:disable Style/GlobalVars
  end

  def gvar_logical_or_assign
    $gvar_logical_or_assign ||= "unknown" # rubocop:disable Style/GlobalVars
  end

  def no_compound_assignment
    "hello"
  end

  def nested_lvar_op_write(x, t)
    x += (t -= 1)
  end

  def nested_ivar_op_write(t)
    @ivar_op += (t -= 1)
  end

  def nested_cvar_op_write(t)
    @@cvar_op += (t -= 1) # rubocop:disable Style/ClassVars
  end

  def nested_gvar_op_write(t)
    $gvar_op += (t -= 1) # rubocop:disable Style/GlobalVars
  end

  def nested_lvar_and_write(x, t)
    x &&= (t -= 1)
  end

  def nested_lvar_or_write(x, t)
    x ||= (t -= 1)
  end

  def nested_ivar_and_write(t)
    @ivar_and &&= (t -= 1)
  end

  def nested_ivar_or_write(t)
    @ivar_or ||= (t -= 1)
  end

  def nested_cvar_and_write(t)
    @@cvar_and &&= (t -= 1) # rubocop:disable Style/ClassVars
  end

  def nested_cvar_or_write(t)
    @@cvar_or ||= (t -= 1) # rubocop:disable Style/ClassVars
  end

  def nested_gvar_and_write(t)
    $gvar_and &&= (t -= 1) # rubocop:disable Style/GlobalVars
  end

  def nested_gvar_or_write(t)
    $gvar_or ||= (t -= 1) # rubocop:disable Style/GlobalVars
  end

  def attribute_add_assign(counter)
    counter.total += 1
  end

  def attribute_subtract_assign(account, amount)
    account.balance -= amount
    account
  end

  def self_attribute_shift_assign
    self.flags <<= 1
  end

  def safe_attribute_multiply_assign(order)
    order&.quantity *= 2
  end

  def chained_attribute_add_assign(order)
    order.totals.net += 5
  end

  def nested_attribute_op_write(counter, t)
    counter.total += (t -= 1)
  end

  def attribute_plain_write(counter)
    counter.total = 1
  end

  def index_add_assign(counts, key)
    counts[key] += 1
  end

  def index_subtract_assign(stock, sku, amount)
    stock[sku] -= amount
    stock
  end

  def self_index_or_bits_assign(bit)
    self[:flags] |= bit
  end

  def safe_index_multiply_assign(totals, key)
    totals&.[](key) || (totals[key] *= 2)
  end

  def chained_index_add_assign(report, key)
    report.totals[key] += 5
  end

  def multiple_index_add_assign(matrix, row, column)
    matrix[row, column] += 1
  end

  def nested_index_op_write(counts, key, t)
    counts[key] += (t -= 1)
  end

  def nested_index_key_op_write(counts, t)
    counts[t -= 1] += 1
  end

  def index_plain_write(counts, key)
    counts[key] = 1
  end
end
