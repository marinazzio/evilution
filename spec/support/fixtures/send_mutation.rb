# frozen_string_literal: true

class SendMutationFixture
  def using_flat_map
    [1, 2, 3].flat_map { |x| [x, x * 2] }
  end

  def using_map
    [1, 2, 3].map { |x| x * 2 }
  end

  def using_public_send
    obj.public_send(:method_name) # rubocop:disable Style/SendWithLiteralMethodName
  end

  def using_send
    obj.send(:method_name)
  end

  def using_gsub
    "hello world".gsub("o", "0")
  end

  def using_sub
    "hello world".sub("o", "0")
  end

  def using_detect
    [1, 2, 3].detect { |x| x > 1 }
  end

  def using_find
    [1, 2, 3].find { |x| x > 1 }
  end

  def using_collect
    [1, 2, 3].collect { |x| x * 2 }
  end

  def using_each_with_object
    [1, 2, 3].each_with_object([]) { |x, acc| acc << x }
  end

  def using_flat_map_and_map
    [1, 2].flat_map { |x| [x].map { |y| y } }
  end

  def using_reverse_each
    [1, 2, 3].reverse_each { |x| puts x }
  end

  def bare_method_call
    flat_map { |x| x }
  end

  def using_length
    [1, 2, 3].length
  end

  def using_size
    [1, 2, 3].size
  end

  def using_values_at
    { a: 1 }.values_at(:a)
  end

  def using_fetch_values
    { a: 1 }.fetch_values(:a)
  end

  def using_sum
    [1, 2, 3].sum
  end

  def using_inject
    [1, 2, 3].inject(0) { |acc, x| acc + x }
  end

  def using_count
    [1, 2, 3].count
  end

  def using_select
    [1, 2, 3].select { |x| x > 1 }
  end

  def using_filter
    [1, 2, 3].filter { |x| x > 1 }
  end

  def using_to_s
    42.to_s
  end

  def using_to_i
    "42".to_i
  end

  def using_to_f
    "3.14".to_f
  end

  def using_to_a
    { a: 1 }.to_a
  end

  def using_to_h
    [[:a, 1]].to_h
  end
end
