# frozen_string_literal: true

require_relative "../operator"

class Evilution::Mutator::Operator::SplatOperator < Evilution::Mutator::Base
  def visit_splat_node(node)
    mutate_remove_splat(node) if node.expression && !exempt_splats.include?(node)

    super
  end

  # Inside a hash literal `**opts` merges a hash in; a bare `opts` is not an
  # element (`{ opts }` is a syntax error), so these splats are skipped.
  def visit_hash_node(node)
    exempt_splats.merge(node.elements.grep(Prism::AssocSplatNode))
    super
  end

  # The rest of a pattern binds what is left over; it is not a splat in a
  # call or a literal, so these splats are skipped. Dropping `**` from
  # `{ key:, **opts }` is a syntax error. Dropping `*` from `[a, *rest]`
  # parses, but it narrows the pattern to a fixed length. That mutant is
  # deliberately not emitted, and the pattern operators keep a binding rest
  # (`*rest`, `**opts`) as written. The rest of a multiple assignment
  # (`a, *b = x`) is still mutated: `a, b = x` parses and changes what `b`
  # binds.
  def visit_hash_pattern_node(node)
    exempt_splats.add(node.rest) if node.rest
    super
  end

  def visit_array_pattern_node(node)
    exempt_splats.add(node.rest) if node.rest
    super
  end

  def visit_find_pattern_node(node)
    exempt_splats.add(node.left)
    exempt_splats.add(node.right)
    super
  end

  # KeywordHashNode wraps call-arg kwargs + `**splat`. When an explicit
  # `k: v` or another `**splat` precedes a `**opts` splat in the same call,
  # demoting `**opts` to bare `opts` puts a positional after a keyword
  # argument and Ruby rejects it (`bar(k: v, opts)` and `bar(**a, opts)` are
  # syntax errors), so such splats are skipped.
  # A splat that comes first (`bar(**opts, k: v)`) is still safe —
  # positional-before-keyword is fine.
  def visit_keyword_hash_node(node)
    exempt_splats.merge(node.elements.drop(1).grep(Prism::AssocSplatNode))
    super
  end

  def visit_assoc_splat_node(node)
    return super if node.value.nil?
    return super if exempt_splats.include?(node)

    mutate_remove_double_splat(node)

    super
  end

  private

  # Splats that are left as written: removing the `*` or `**` would not
  # parse, or would change what a pattern matches. Each visitor that fills
  # the set says why.
  def exempt_splats
    @exempt_splats ||= Set.new.compare_by_identity
  end

  def mutate_remove_splat(node)
    add_mutation(
      offset: node.location.start_offset,
      length: node.location.length,
      replacement: node.expression.slice,
      node: node
    )
  end

  def mutate_remove_double_splat(node)
    add_mutation(
      offset: node.location.start_offset,
      length: node.location.length,
      replacement: node.value.slice,
      node: node
    )
  end
end
