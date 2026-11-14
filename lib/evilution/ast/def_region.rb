# frozen_string_literal: true

require "prism"
require_relative "../ast"
require_relative "syntax_check"

# Checks a mutation made inside a method by parsing the method alone rather
# than the whole file around it.
#
# A file is parsed whole to tell whether a mutation of it is still Ruby,
# which costs per mutation what the file is long. A `def ... end` closes the
# scope its body is read in: what the body may hold, and how its names read,
# does not depend on the code around it. So when the original file parses
# and the mutated def parses on its own as one `def ... end` spanning all of
# its text, the mutated file parses too, the def standing where the original
# stood.
#
# Where that does not follow, or might not, #parse is nil and the caller
# parses the whole file as before, so no mutation the whole file rejects is
# ever taken:
# - an endless def, which the text after it can extend;
# - a def on a receiver other than self, which is read in the outer scope;
# - a def whose line holds anything but names before it (`private def`),
#   which could open a heredoc whose body runs through the def;
# - a file that names its encoding, which changes what its strings may hold;
# - a mutation that reaches outside the def.
class Evilution::AST::DefRegion
  # node: the mutated def; source: the text it was parsed from, the def's
  # own with the names before it on its line blanked, so its columns stay as
  # they were; span: the offsets the original def takes up in the file;
  # offset, length, replacement: the mutation.
  Region = Data.define(:node, :source, :span, :offset, :length, :replacement)

  NAMES_BEFORE_DEF = /\A[ \t]*(?:[a-z_][a-zA-Z0-9_]*[ \t]+)*\z/n
  ENCODING_COMMENT = /coding/i
  private_constant :NAMES_BEFORE_DEF, :ENCODING_COMMENT

  def initialize(source, node, prism_interpreter: Evilution::AST::SyntaxCheck::PRISM_INTERPRETER)
    @source = source
    @node = node
    @prism_interpreter = prism_interpreter
  end

  # The mutated def's Region when the def proves the mutated file parses,
  # nil otherwise.
  def parse(offset:, length:, replacement:)
    return unless covers?(offset, length) && checkable?

    text = mutated_text(offset, length, replacement)
    result = Prism.parse(text)
    return unless result.success?

    statements = result.value.statements.body
    return unless statements.length == 1 && whole_def?(statements.first, text)

    Region.new(node: statements.first, source: text, span: @node.start_offset..@node.end_offset,
               offset: offset, length: length, replacement: replacement)
  end

  private

  def covers?(offset, length)
    @node.is_a?(Prism::DefNode) && offset >= @node.start_offset && offset + length <= @node.end_offset
  end

  def checkable?
    return @checkable if defined?(@checkable)

    @checkable = closed_def?(@node) && in_place? && names_before? && !names_encoding?
  end

  def closed_def?(node)
    !node.end_keyword_loc.nil? && (node.receiver.nil? || node.receiver.is_a?(Prism::SelfNode))
  end

  # The node is the def written at its offsets in this source.
  def in_place?
    @source.byteslice(@node.start_offset, @node.end_offset - @node.start_offset) == @node.slice
  end

  def names_before?
    prefix.match?(NAMES_BEFORE_DEF)
  end

  # Ruby reads an encoding comment on the first line, or on the second after
  # a shebang.
  def names_encoding?
    bytes = @source.b
    first_break = bytes.index("\n")
    second_break = first_break && bytes.index("\n", first_break + 1)
    bytes.byteslice(0, second_break || bytes.bytesize).match?(ENCODING_COMMENT)
  end

  def prefix
    @prefix ||= begin
      bytes = @source.b
      line_break = @node.start_offset.zero? ? nil : bytes.rindex("\n", @node.start_offset - 1)
      line_start = line_break ? line_break + 1 : 0
      bytes.byteslice(line_start, @node.start_offset - line_start)
    end
  end

  def mutated_text(offset, length, replacement)
    text = " " * prefix.bytesize
    text << bytes_between(@node.start_offset, offset) << replacement.b
    text << bytes_between(offset + length, @node.end_offset)
    text.force_encoding(@source.encoding)
  end

  def bytes_between(from, to)
    @source.b.byteslice(from, to - from)
  end

  def whole_def?(node, text)
    node.is_a?(Prism::DefNode) && closed_def?(node) &&
      node.start_offset == prefix.bytesize && node.end_offset == text.bytesize &&
      (@prism_interpreter || Evilution::AST::SyntaxCheck.parse_y_accepts?(text))
  end
end
