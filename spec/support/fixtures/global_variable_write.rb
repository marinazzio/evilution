class GvarExample
  def with_gvars
    $verbose = true
    $count = 0
    $count
  end

  def single_gvar
    $output = compute
    $output
  end

  def no_gvars
    42
  end
end
