# frozen_string_literal: true

require "prism"

require_relative "../operator"

# Replace a single-expression method body with the empty value of the type it
# returns: `def names(users); users.map(&:name); end` becomes
# `def names(users); []; end`.
#
# A survivor means the suite asserts the shape of the returned value but never
# its content — a test that only checks `be_an(Array)`, or that calls the method
# for its side effects and ignores what comes back.
#
# CollectionReturn and ScalarReturn do this for bodies of two or more
# statements, and the literal operators (array_literal, hash_literal,
# string_literal, integer_literal, float_literal) cover a body that is itself a
# literal. What neither reaches is the single-expression body whose type is not
# written down — the common shape of readers and builders — so the type is taken
# from the trailing call's selector instead.
#
# Only selectors whose return type is fixed by Ruby (or a widely-used extension with a stable contract,
# e.g. ActiveSupport's `index_by`) are listed.
# A method of the same name defined elsewhere can still return something else,
# in which case the mutant raises where it is consumed and dies on contact; the
# table is kept narrow to make that rare.
class Evilution::Mutator::Operator::TypedDefaultReturn < Evilution::Mutator::Base
  SELECTOR_TYPES = {
    "[]" => %i[map collect select filter reject sort sort_by to_a compact flatten values keys uniq],
    "{}" => %i[to_h group_by tally index_by transform_values transform_keys],
    "0" => %i[count size length],
    '""' => %i[to_s join upcase downcase strip]
  }.freeze

  REPLACEMENT_BY_SELECTOR = SELECTOR_TYPES.flat_map do |replacement, selectors|
    selectors.map { |selector| [selector, replacement] }
  end.to_h.freeze
  private_constant :REPLACEMENT_BY_SELECTOR

  def visit_def_node(node)
    replace_body_with_default(node)
    super
  end

  private

  def replace_body_with_default(node)
    statements = body_statements(node.body)
    return if statements.nil?
    return unless statements.body.length == 1

    replacement = default_for(statements.body.first)
    return if replacement.nil?

    location = statements.location

    add_mutation(
      offset: location.start_offset,
      length: location.length,
      replacement: replacement,
      node: node
    )
  end

  # A method-level rescue/ensure (`def foo; stmts; rescue; ...; end`) makes the
  # body a BeginNode whose location spans the entire `def...end`, keyword and
  # matching `end` included. Replacing that range would delete the method
  # framing, so only the leading statements are replaceable. Returns nil for a
  # rescue/ensure-only body and for an empty method, whose body is nil.
  def body_statements(body)
    return body unless body.is_a?(Prism::BeginNode)

    body.statements
  end

  # A body that is already a literal is left to the literal operators, which
  # emit the same empty value for it.
  def default_for(node)
    case node
    when Prism::InterpolatedStringNode then '""'
    when Prism::CallNode then REPLACEMENT_BY_SELECTOR[node.name]
    end
  end
end
