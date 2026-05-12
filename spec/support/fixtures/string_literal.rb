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
end
