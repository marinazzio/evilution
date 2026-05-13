class StringChecker
  def returns_hello
    "hello"
  end

  def returns_empty
    ""
  end

  def returns_heredoc
    <<~HEREDOC
      some template text
    HEREDOC
  end

  def returns_heredoc_with_interpolation
    name = "world"
    <<~HEREDOC
      hello #{name} today
    HEREDOC
  end

  def returns_heredoc_with_string_in_interpolation
    <<~HEREDOC
      hello #{"literal"} world
    HEREDOC
  end

  def returns_backslash_chained
    "alpha " \
      "beta " \
      "gamma"
  end

  def returns_two_chunk_chain
    "left " \
      "right"
  end

  def returns_same_line_adjacent
    "foo " "bar"
  end

  def returns_plain_plus_interp_continued
    "RuboCop supports target Ruby versions 3.4 and below with " \
      "`parser`. Specified target Ruby version: #{ruby_version.inspect}"
  end

  def returns_interp_plus_plain_continued
    "Specified target Ruby version: #{ruby_version.inspect}" \
      " is not supported. Pin to 3.4 or earlier."
  end

  def ruby_version
    "4.0"
  end

  def returns_plain_interpolated
    name = "world"
    "hello #{name}"
  end

  def returns_pure_interpolation
    a = "1"
    b = "2"
    "#{a}#{b}"
  end

  def returns_interpolated_symbol
    type = "node"
    send(:"visit_#{type}")
  end

  def returns_interpolated_regex
    needle = "foo"
    "foobar".match?(/^#{needle}/)
  end

  def returns_interpolated_xstring
    cmd = "ls"
    `echo #{cmd}`
  end

  def returns_plain_symbol
    :a_plain_symbol
  end
end
