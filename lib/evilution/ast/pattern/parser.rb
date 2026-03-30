# frozen_string_literal: true

require_relative "matcher"

class Evilution::AST::Pattern::Parser
  def initialize(input)
    @input = input.strip
    @pos = 0
  end

  def parse
    raise Evilution::ConfigError, "invalid pattern: empty string" if @input.empty?

    result = parse_pattern
    skip_whitespace
    raise Evilution::ConfigError, "unexpected characters at position #{@pos}: #{@input[@pos..]}" unless @pos >= @input.length

    result
  end

  private

  def parse_pattern
    skip_whitespace

    if peek_string("**")
      advance(2)
      Evilution::AST::Pattern::DeepWildcardMatcher.new
    elsif current_char == "_" && !identifier_continues?(1)
      advance(1)
      Evilution::AST::Pattern::AnyNodeMatcher.new
    else
      parse_node_pattern
    end
  end

  def parse_node_pattern
    node_type = consume_identifier
    skip_whitespace

    attributes = {}
    if current_char == "{"
      advance(1)
      attributes = parse_attributes
      skip_whitespace
      expect_char("}")
    end

    Evilution::AST::Pattern::NodeMatcher.new(node_type, attributes)
  end

  def parse_attributes
    attrs = {}
    skip_whitespace

    return attrs if current_char == "}"

    loop do
      skip_whitespace
      name = consume_identifier
      skip_whitespace
      expect_char("=", "expected '=' after attribute name '#{name}'")
      skip_whitespace
      value = parse_value
      attrs[name] = value
      skip_whitespace

      break unless current_char == ","

      advance(1)
    end

    attrs
  end

  def parse_value
    skip_whitespace

    if current_char == "!"
      advance(1)
      skip_whitespace
      inner = parse_value
      Evilution::AST::Pattern::NegationMatcher.new(inner)
    elsif current_char == "*" && !peek_string("**")
      advance(1)
      Evilution::AST::Pattern::WildcardValueMatcher.new
    elsif peek_string("**")
      advance(2)
      Evilution::AST::Pattern::DeepWildcardMatcher.new
    elsif current_char == "_" && !identifier_continues?(1)
      advance(1)
      Evilution::AST::Pattern::AnyNodeMatcher.new
    else
      parse_value_or_nested
    end
  end

  def parse_value_or_nested
    id = consume_identifier
    skip_whitespace

    if current_char == "{"
      advance(1)
      attrs = parse_attributes
      skip_whitespace
      expect_char("}")
      Evilution::AST::Pattern::NodeMatcher.new(id, attrs)
    else
      parse_alternatives_from(id)
    end
  end

  def parse_alternatives_from(first)
    values = [first]

    while current_char == "|"
      advance(1)
      skip_whitespace
      values << consume_identifier
    end

    if values.length == 1
      Evilution::AST::Pattern::ValueMatcher.new(first)
    else
      Evilution::AST::Pattern::AlternativesMatcher.new(values)
    end
  end

  def consume_identifier
    start = @pos
    advance(1) while @pos < @input.length && @input[@pos].match?(/[a-zA-Z0-9_]/)
    raise Evilution::ConfigError, "unexpected end of pattern at position #{@pos}" if @pos == start

    @input[start...@pos]
  end

  def skip_whitespace
    advance(1) while @pos < @input.length && @input[@pos] == " "
  end

  def current_char
    @pos < @input.length ? @input[@pos] : nil
  end

  def peek_string(str)
    @input[@pos, str.length] == str
  end

  def identifier_continues?(offset)
    char = @input[@pos + offset]
    char && char.match?(/[a-zA-Z0-9_]/)
  end

  def advance(n)
    @pos += n
  end

  def expect_char(char, message = nil)
    raise Evilution::ConfigError, message || "unexpected end of pattern, expected '#{char}' at position #{@pos}" if current_char != char

    advance(1)
  end
end
