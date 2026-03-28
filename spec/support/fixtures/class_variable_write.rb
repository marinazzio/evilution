class CvarExample
  def with_cvars
    @@count = 0
    @@name = "default"
    @@count
  end

  def single_cvar
    @@total = compute
    @@total
  end

  def no_cvars
    42
  end
end
