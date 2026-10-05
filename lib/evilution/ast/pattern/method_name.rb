# frozen_string_literal: true

require_relative "../pattern"

# Reads a method name the way an attribute value spells it: an identifier with
# an optional `?`, `!` or `=`, a bare operator, or anything else in quotes.
class Evilution::AST::Pattern::MethodName
  # Longest first, so `<=>` is not read as `<=`. Operators starting with `!`,
  # `*` or `|` already mean negation, a wildcard or an alternative in a
  # pattern, and have to be quoted.
  OPERATORS = %w[<=> === == =~ []= [] <= << < >= >> > +@ -@ + - / % & ^ ~].freeze
  IDENTIFIER = /\G[a-zA-Z_][a-zA-Z0-9_]*[?!=]?/
  QUOTES = %w[' "].freeze

  # The name starting at +pos+ in +input+, and the position just after it.
  def self.scan(input, pos)
    new(input, pos).scan
  end

  def initialize(input, pos)
    @input = input
    @pos = pos
  end

  def scan
    char = @input[@pos]
    raise Evilution::ConfigError, "unexpected end of pattern at position #{@pos}" if char.nil?

    name = QUOTES.include?(char) ? quoted(char) : operator || identifier(char)
    [name, @pos]
  end

  private

  def quoted(quote)
    finish = @input.index(quote, @pos + 1)
    raise Evilution::ConfigError, "unterminated quoted name starting at position #{@pos}" if finish.nil?

    name = @input[(@pos + 1)...finish]
    raise Evilution::ConfigError, "empty quoted name at position #{@pos}" if name.empty?

    @pos = finish + 1
    name
  end

  def operator
    name = OPERATORS.find { |candidate| @input[@pos, candidate.length] == candidate }
    @pos += name.length if name
    name
  end

  def identifier(char)
    match = IDENTIFIER.match(@input, @pos)
    if match.nil?
      raise Evilution::ConfigError,
            "invalid name starting with '#{char}' at position #{@pos}; " \
            "quote names that are not identifiers or operators, e.g. name='|'"
    end

    @pos = match.end(0)
    match[0]
  end
end
