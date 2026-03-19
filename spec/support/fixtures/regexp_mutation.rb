class RegexpMutationExample
  def simple_match(str)
    str.match?(/foo/)
  end

  def with_flags(str)
    str.match?(/bar/i)
  end

  def complex_pattern(str)
    str.scan(/\d+/)
  end

  def no_regexp(str)
    str.upcase
  end

  def case_match(str)
    case str
    when /^hello/
      "greeting"
    end
  end
end
