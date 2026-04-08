# frozen_string_literal: true

# rubocop:disable Lint/LiteralInInterpolation
class HeredocMutations
  def plain_heredoc
    <<~HEREDOC
      some template text
    HEREDOC
  end

  def squiggly_heredoc
    <<~SQL
      SELECT * FROM users
      WHERE active = true
    SQL
  end

  def non_squiggly_heredoc
    <<HEREDOC
  fixed layout text
HEREDOC
  end

  def dash_heredoc
    <<-HEREDOC
      indented closing
    HEREDOC
  end

  def single_quote_heredoc
    <<~'HEREDOC'
      no #{interpolation} here
    HEREDOC
  end

  def interpolated_heredoc
    table = "users"
    <<~SQL
      SELECT * FROM #{table}
      WHERE id = #{42}
    SQL
  end

  def heredoc_with_string_in_interpolation
    <<~HEREDOC
      hello #{"world"} today
    HEREDOC
  end

  def nested_heredoc
    first = <<~FIRST
      first heredoc
    FIRST
    second = <<~SECOND
      second heredoc
    SECOND
    first + second
  end

  def mixed_heredoc_and_strings
    prefix = "start"
    body = <<~HEREDOC
      template #{prefix} content
    HEREDOC
    suffix = "end"
    prefix + body + suffix
  end
end
# rubocop:enable Lint/LiteralInInterpolation
