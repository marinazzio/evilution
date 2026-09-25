class RegexpAnchorTarget
  def line_prefix(line)
    line =~ /^foo/
  end

  def string_prefix_match(line)
    line =~ /\Afoo/
  end

  def dollar_suffix(line)
    line.match?(/bar$/)
  end

  def newline_suffix(line)
    line.match(/bar\Z/)
  end

  def string_suffix_match(line)
    line.match(/bar\z/)
  end

  def escaped_literal(host)
    host.match?(/\.example\.com$/)
  end

  def regexp_on_the_left(line)
    /^foo/ =~ line
  end

  def regexp_receiver_match(line)
    /^foo/.match?(line)
  end

  def exact_predicate_prefix(line)
    line.match?(/\Afoo/)
  end

  def exact_predicate_suffix(line)
    line.match?(/bar\z/)
  end

  def both_anchors(line)
    line =~ /\Afoo\z/
  end

  def character_class(line)
    line =~ /^\d/
  end

  def metacharacter(line)
    line =~ /^fo.o/
  end

  def with_flag(line)
    line =~ /^foo/i
  end

  def unanchored(line)
    line =~ /foo/
  end

  def interpolated(line, prefix)
    line =~ /^#{prefix}/
  end

  def position_argument(line)
    line.match(/^foo/, 2)
  end

  def implicit_receiver
    match?(/^foo/)
  end
end
