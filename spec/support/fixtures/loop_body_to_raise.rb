class LoopBodyToRaiseTarget
  def count_up(limit)
    i = 0
    while i < limit
      i += 1
    end
    i
  end

  def count_down(n)
    until n.zero?
      n -= 1
    end
    n
  end

  def multi_statement(items)
    while items.any?
      item = items.pop
      yield item
    end
  end

  def modifier(queue)
    queue.pop while queue.any?
  end

  def post_form(queue)
    begin
      queue.pop
    end while queue.any?
  end

  def post_form_until(queue)
    begin
      queue.pop
    end until queue.empty?
  end

  def empty_body(flag)
    while flag
    end
  end

  def already_raises(flag)
    while flag
      raise
    end
  end

  def literal_body(flag)
    while flag
      1
    end
  end

  def bare_call_body(flag)
    while flag
      step
    end
  end

  def raise_comes_first(queue)
    while queue.any?
      raise
      queue.pop
    end
  end

  def raises_with_message(flag)
    while flag
      raise "boom"
    end
  end

  def raises_via_receiver(flag)
    while flag
      Kernel.raise
    end
  end

  def raise_is_not_alone(queue)
    while queue.any?
      queue.pop
      raise
    end
  end

  def post_form_with_rescue(queue)
    begin
      queue.pop
    rescue StandardError
      nil
    end while queue.any?
  end

  def nested_until(rows, cols)
    until rows.empty?
      until cols.empty?
        cols.pop
      end
      rows.pop
    end
  end

  def nested(rows, cols)
    while rows.any?
      row = rows.pop
      while cols.any?
        cols.pop
      end
      row
    end
  end
end
