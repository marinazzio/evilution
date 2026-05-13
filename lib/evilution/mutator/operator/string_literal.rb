# frozen_string_literal: true

require_relative "../operator"

class Evilution::Mutator::Operator::StringLiteral < Evilution::Mutator::Base
  def initialize(skip_heredoc_literals: false, **rest)
    super(**rest)
    @skip_heredoc_literals = skip_heredoc_literals
  end

  def visit_interpolated_string_node(node)
    if node.heredoc?
      return if @skip_heredoc_literals

      node.parts.each do |part|
        next if part.is_a?(Prism::StringNode)

        visit(part)
      end
      return
    end

    # Adjacent-string concatenation — both `"foo" "bar"` and the line-continued
    # form `"foo" \\\n "bar"` — lands in an InterpolatedStringNode whose parts
    # are all StringNodes. Mutating chunks individually splices the wrong span:
    # for the continued form Ruby treats `nil \\\n "rest"` as a confusing
    # parse rather than a clean nil; for both forms the result is one StringNode
    # plus an orphaned adjacent literal, not a meaningful mutation of the whole
    # expression. Replace the entire concatenation in one shot instead.
    if adjacent_string_concat?(node)
      emit_string_mutations(node)
      return
    end

    super
  end

  def visit_string_node(node)
    return super if node.heredoc?

    emit_string_mutations(node)

    super
  end

  # Inner StringNode chunks of an interpolated symbol (`:"visit_#{type}"`),
  # interpolated regular expression (`/^#{needle}/`), or interpolated x-string
  # (`` `echo #{cmd}` ``) are not free string literals — they are fragments of
  # a different literal kind. Mutating them splices empty-string bytes into the
  # middle of a `:"..."` / `/.../` / `` `...` `` token, producing unparseable
  # code. Visit only the interpolation parts (which may contain mutatable
  # expressions); skip the raw StringNode chunks.
  def visit_interpolated_symbol_node(node)
    visit_non_string_parts(node)
  end

  def visit_interpolated_regular_expression_node(node)
    visit_non_string_parts(node)
  end

  def visit_interpolated_x_string_node(node)
    visit_non_string_parts(node)
  end

  private

  def visit_non_string_parts(node)
    node.parts.each do |part|
      next if part.is_a?(Prism::StringNode)

      visit(part)
    end
  end

  # Adjacent-string concatenation differs from a single interpolated string by
  # the shape of its parts: each adjacent chunk is a full quoted literal of its
  # own — a StringNode or InterpolatedStringNode that owns its own opening
  # quote (`opening_loc`). A plain interpolated string `"a #{x} b"` decomposes
  # into chunk StringNodes (no `opening_loc`) interleaved with
  # EmbeddedStatementsNode parts (whose `opening_loc` is the `#{` delimiter,
  # not a quote). Requiring StringNode/InterpolatedStringNode AND `opening_loc`
  # rejects pure-interpolation cases like `"#{a}#{b}"` (whose parts are all
  # EmbeddedStatementsNodes) while accepting mixed plain+interpolated adjacency
  # like `"foo" "bar #{x}"` and its line-continued cousin.
  QUOTED_LITERAL_TYPES = [Prism::StringNode, Prism::InterpolatedStringNode].freeze
  private_constant :QUOTED_LITERAL_TYPES

  def adjacent_string_concat?(node)
    return false unless node.parts.length > 1

    node.parts.all? do |part|
      QUOTED_LITERAL_TYPES.any? { |type| part.is_a?(type) } && part.opening_loc
    end
  end

  def emit_string_mutations(node)
    empty = node_content_empty?(node)
    replacement = empty ? '"mutation"' : '""'

    add_mutation(
      offset: node.location.start_offset,
      length: node.location.length,
      replacement: replacement,
      node: node
    )

    add_mutation(
      offset: node.location.start_offset,
      length: node.location.length,
      replacement: "nil",
      node: node
    )
  end

  def node_content_empty?(node)
    return node.content.empty? if node.is_a?(Prism::StringNode)

    node.parts.all? { |part| part.is_a?(Prism::StringNode) && part.content.empty? }
  end
end
