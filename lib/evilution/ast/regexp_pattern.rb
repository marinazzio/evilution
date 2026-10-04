# frozen_string_literal: true

require "prism"
require "regexp_parser"

require_relative "../ast"

# The pattern of a regexp literal, parsed with regexp_parser and addressed by
# byte offsets into the file, for operators that mutate a regexp's structure.
#
# Edits are made by offsets into the original source, never by re-emitting the
# pattern, so everything outside an edit stays byte for byte as written.
#
# regexp_parser counts offsets in characters; they are converted to bytes here
# so they can go straight to source surgery. Prism accepts patterns whose
# references point nowhere (`/(?:a)\1/`), so an edit has to be compiled before
# it is emitted: `#compiles?` does that.
class Evilution::AST::RegexpPattern
  Token = Data.define(:type, :token, :text, :start_offset, :end_offset)

  attr_reader :tokens

  # Returns nil for anything but a plain regexp literal — interpolated
  # patterns are only known at runtime — and when regexp_parser cannot read
  # the pattern (including one that is not valid in its encoding), so callers
  # simply emit no mutants.
  def self.parse(node)
    return nil unless node.is_a?(Prism::RegularExpressionNode)

    new(node)
  rescue Regexp::Parser::Error
    nil
  end

  def initialize(node)
    @text = node.content_loc.slice
    @base_offset = node.content_loc.start_offset
    @options = options_of(node)
    @byte_offsets = byte_offsets_of(@text)
    @tokens = scan_tokens
    @root = Regexp::Parser.parse(@text, options: @options)
  end

  # Yields every expression of the parsed pattern with its start and end
  # offsets in the file.
  def each_expression
    @root.each_expression do |expression, _index|
      yield expression, *offsets(expression)
    end
  end

  # An expression's start and end offsets in the file, quantifier included.
  def offsets(expression)
    [file_offset(expression.ts), file_offset(expression.ts + expression.full_length)]
  end

  # Whether the pattern still compiles once the span between the two file
  # offsets is replaced.
  def compiles?(start_offset, end_offset, replacement)
    local_start = start_offset - @base_offset
    mutated = @text.byteslice(0, local_start) + replacement + @text.byteslice((end_offset - @base_offset)..)
    without_warnings { Regexp.new(mutated, @options) }
    true
  rescue RegexpError
    false
  end

  private

  # Only extended mode changes how a pattern is read: whitespace and `#`
  # comments become tokens of their own. Case-insensitivity and multiline
  # change what a pattern matches, not how it parses or whether it compiles.
  def options_of(node)
    node.extended? ? Regexp::EXTENDED : 0
  end

  # Bytes before each character position, one entry past the last character.
  def byte_offsets_of(text)
    offsets = [0]
    text.each_char { |char| offsets << (offsets.last + char.bytesize) }
    offsets
  end

  def file_offset(character_index)
    @base_offset + @byte_offsets.fetch(character_index)
  end

  def scan_tokens
    Regexp::Scanner.scan(@text, options: @options).map do |type, token, text, start_index, end_index|
      Token.new(type: type, token: token, text: text,
                start_offset: file_offset(start_index), end_offset: file_offset(end_index))
    end
  end

  # Onigmo warns about patterns such as duplicated class ranges; a mutant can
  # produce them, and the warning would land in the user's output.
  def without_warnings
    verbose = $VERBOSE
    $VERBOSE = nil
    yield
  ensure
    $VERBOSE = verbose
  end
end
