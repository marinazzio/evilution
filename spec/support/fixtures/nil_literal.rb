class NilChecker
  def returns_nil
    nil
  end

  def nil_with_logic(flag)
    return nil if flag
    42
  end
end
