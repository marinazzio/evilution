class SymbolToProcTarget
  def stringify(items)
    items.map(&:to_s)
  end

  def firsts(pairs)
    pairs.map(&:first)
  end

  def multiple(words)
    words.map(&:strip)
  end

  def nested_map(lists)
    lists.each(&:map)
  end

  def quoted(items)
    items.map(&:"upcase")
  end

  def unknown_selector(users)
    users.map(&:name)
  end

  def alias_only(items)
    items.map(&:length)
  end

  def block_variable(items, block)
    items.map(&block)
  end

  def literal_block(items)
    items.map { |item| item.to_s }
  end
end
