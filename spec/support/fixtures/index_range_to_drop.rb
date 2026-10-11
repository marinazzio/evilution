class IndexRangeToDropTarget
  def literal_start(list)
    list[1..-1]
  end

  def variable_start(list, offset)
    list[offset..-1]
  end

  def expression_start(list, index)
    list[index + 1..-1]
  end

  def endless(list, offset)
    list[offset..]
  end

  def endless_exclusive(list, offset)
    list[offset...]
  end

  def chained_receiver(report, offset)
    report.rows[offset..-1]
  end

  def assigned(list, offset)
    rest = list[offset..-1]
    rest
  end

  def receiver_of_call(list, offset)
    list[offset..-1].first
  end

  def safe_navigation(list, offset)
    list&.[](offset..-1)
  end

  def void_statement(list, offset)
    list[offset..-1]
    true
  end

  def zero_start(list)
    list[0..-1]
  end

  def negative_start(list)
    list[-2..-1]
  end

  def beginless(list)
    list[..-1]
  end

  def exclusive_end(list, offset)
    list[offset...-1]
  end

  def other_end(list, offset)
    list[offset..-2]
  end

  def variable_end(list, offset, last)
    list[offset..last]
  end

  def start_and_length(list, offset)
    list[offset, -1]
  end

  def range_and_argument(list, offset, extra)
    list[offset..-1, extra]
  end

  def plain_index(list, offset)
    list[offset]
  end

  def index_write(list, offset, tail)
    list[offset..-1] = tail
  end

  def named_call(list, offset)
    list.slice(offset..-1)
  end
end
