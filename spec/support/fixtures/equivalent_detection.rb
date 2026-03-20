# frozen_string_literal: true

class EquivalentDetectionFixture
  def empty_method; end

  def nil_method
    nil
  end

  def normal_method
    x = 1
    x + 2
  end

  def method_with_dead_code
    return 42
    puts "unreachable" # rubocop:disable Lint/UnreachableCode
    "dead"
  end

  def method_with_raise_dead_code
    raise "error"
    cleanup # rubocop:disable Lint/UnreachableCode
  end

  def method_with_conditional_return(x)
    return 42 if x > 0

    x + 1
  end

  def using_detect
    [1, 2, 3].detect { |x| x > 1 }
  end

  def using_find
    [1, 2, 3].find { |x| x > 1 }
  end

  def using_length
    [1, 2, 3].length
  end

  def using_size
    [1, 2, 3].size
  end

  def using_collect
    [1, 2, 3].collect { |x| x * 2 }
  end

  def using_flat_map
    [1, 2, 3].flat_map { |x| [x] }
  end
end
