# frozen_string_literal: true

require_relative "../operator"

# Resolve a dynamic constant lookup with a literal name into a constant path:
# `Registry.const_get(:Handler)` becomes `Registry::Handler`. A literal
# inherit flag is dropped; a receiverless call resolves against `self`.
#
# The two find the same own, inherited and mixed-in constants and raise the
# same NameError for a missing one. They differ on top-level constants (found
# by `const_get` through Object, rejected by `::`), on private constants
# (returned by `const_get` only) and with `inherit = false` (ancestors skipped
# by `const_get`, searched by `::`). A survivor means none of those paths is
# exercised, so the dynamic lookup may not be needed.
#
# Safe navigation is skipped: a constant path has no nil-safe form.
class Evilution::Mutator::Operator::ConstGetToConstantPath < Evilution::Mutator::Base
  CONSTANT_NAME = /\A[A-Z]\w*\z/
  private_constant :CONSTANT_NAME

  INHERIT_FLAGS = [Prism::TrueNode, Prism::FalseNode].freeze
  private_constant :INHERIT_FLAGS

  def visit_call_node(node)
    rewrite(node) if node.name == :const_get && node.block.nil? && !node.safe_navigation?
    super
  end

  private

  def rewrite(node)
    name = constant_name(node)
    return if name.nil?

    receiver = node.receiver ? source_of(node.receiver) : "self"
    add_mutation(offset: node.start_offset, length: node.location.length, replacement: "#{receiver}::#{name}", node: node)
  end

  def constant_name(node)
    return unless node.arguments in Prism::ArgumentsNode[arguments: [Prism::SymbolNode => symbol, *flags]]
    return unless flags.empty? || literal_inherit_flag?(flags)

    symbol.unescaped if symbol.unescaped.match?(CONSTANT_NAME)
  end

  def literal_inherit_flag?(flags)
    flags.length == 1 && INHERIT_FLAGS.any? { |type| flags.first.is_a?(type) }
  end
end
