# frozen_string_literal: true

require "prism"

require_relative "../ast"

# Computes the byte-length needed for a mutation whose target range contains
# heredoc anchors (`<<~MARKER` / `<<-MARKER` / `<<MARKER`).
#
# Prism reports a heredoc anchor's `location` as the inline range of just
# `<<~MARKER` — the body lines and the closing terminator live in `closing_loc`
# which is on a later line. An operator that builds a byte edit from the
# anchor's inline range (e.g. `argument_removal` using
# `node.arguments.location`) covers the anchor but leaves the body+terminator
# in place, producing an orphaned heredoc fragment that the parser rejects.
#
# `extend_length` walks the supplied AST node for heredoc descendants whose
# anchor falls inside `[offset, offset + length)` and returns a length wide
# enough to also cover those descendants' `closing_loc.end_offset` — so the
# mutation's `replacement` replaces the heredoc body and terminator along with
# the anchor.
module Evilution::AST::HeredocSpan
  module_function

  def extend_length(node:, offset:, length:)
    return length if node.nil?

    end_offset = offset + length
    max_end = end_offset
    Walker.new(offset, end_offset) do |closing_end|
      max_end = closing_end if closing_end > max_end
    end.visit(node)
    max_end - offset
  end

  class Walker < Prism::Visitor
    def initialize(start_offset, end_offset, &block)
      super()
      @start_offset = start_offset
      @end_offset = end_offset
      @block = block
    end

    def visit_string_node(node)
      record_if_heredoc(node)
      super
    end

    def visit_interpolated_string_node(node)
      record_if_heredoc(node)
      super
    end

    def visit_x_string_node(node)
      record_if_heredoc(node)
      super
    end

    def visit_interpolated_x_string_node(node)
      record_if_heredoc(node)
      super
    end

    private

    def record_if_heredoc(node)
      return unless heredoc?(node)

      closing = node.closing_loc
      return unless anchor_in_range?(node) && closing

      @block.call(closing_end_excluding_trailing_newline(closing))
    end

    def heredoc?(node)
      node.respond_to?(:heredoc?) && node.heredoc?
    end

    # Anchor must be inside the mutation's target range; only then does its
    # heredoc body sit outside the range and need pulling in.
    def anchor_in_range?(node)
      opening = node.opening_loc
      return false if opening.nil?

      opening.start_offset >= @start_offset && opening.start_offset < @end_offset
    end

    # Prism's closing_loc covers the terminator including the trailing
    # newline. Excluding that newline preserves line structure after the
    # replacement (any code that follows lands on its own line).
    def closing_end_excluding_trailing_newline(closing)
      end_off = closing.end_offset
      slice = closing.slice
      end_off -= 1 if slice && slice.end_with?("\n")
      end_off
    end
  end
  private_constant :Walker
end
