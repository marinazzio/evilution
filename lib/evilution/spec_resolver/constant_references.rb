# frozen_string_literal: true

require "prism"
require_relative "../spec_resolver"

# The constants a Ruby file refers to, read from Prism's token stream rather
# than from raw text: a name inside a comment, a string, a heredoc or an
# embedded document is not a reference, while one inside string interpolation
# is. Lexing needs no parse tree, so the cost stays close to a regex scan.
class Evilution::SpecResolver::ConstantReferences
  # Tokens after which a `describe` identifier is not a call to describe.
  NOT_A_CALL = %i[SYMBOL_BEGIN KEYWORD_DEF].freeze
  RECEIVER_SEPARATORS = %i[DOT AMPERSAND_DOT].freeze
  OPENING_PARENTHESES = %i[PARENTHESIS_LEFT PARENTHESIS_LEFT_PARENTHESES].freeze

  def initialize(text)
    @tokens = Prism.lex(text).value.map(&:first)
  end

  # Every constant segment, so Timeline::NightWarnings::LIMIT yields all three.
  # A symbol spelled like a constant (:Round) is not a reference.
  def constants
    [nil, *@tokens].each_cons(2).filter_map do |previous, token|
      token.value if token.type == :CONSTANT && !(previous && previous.type == :SYMBOL_BEGIN)
    end
  end

  # The last segment of the constant passed to the file's first `describe`
  # (bare or `RSpec.`), or nil when there is none or it is given anything else,
  # such as a string. Later, nested describes never count.
  def describe_constant
    index = @tokens.each_index.find { |i| describe_call?(i) }
    index && constant_path_after(index + 1)
  end

  private

  def describe_call?(index)
    token = @tokens[index]
    return false unless token.type == :IDENTIFIER && token.value == "describe"
    return true if index.zero?

    previous = @tokens[index - 1].type
    return rspec?(@tokens[index - 2]) if RECEIVER_SEPARATORS.include?(previous)

    !NOT_A_CALL.include?(previous)
  end

  def rspec?(token)
    token.type == :CONSTANT && token.value == "RSpec"
  end

  # The token stream always ends with EOF, so lookahead never runs off the end.
  def constant_path_after(index)
    index += 1 if OPENING_PARENTHESES.include?(@tokens[index].type)
    index += 1 if @tokens[index].type == :UCOLON_COLON
    last = nil
    while @tokens[index].type == :CONSTANT
      last = @tokens[index].value
      break unless @tokens[index + 1].type == :COLON_COLON

      index += 2
    end
    last
  end
end
