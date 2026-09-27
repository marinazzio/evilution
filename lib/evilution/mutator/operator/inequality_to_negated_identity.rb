# frozen_string_literal: true

require_relative "../operator"

# Rewrite an inequality with stricter comparisons: `a != b` becomes
# `!a.eql?(b)` and `!a.equal?(b)`.
#
# `eql?` adds a type check (`1 != 1.0` is false, `!1.eql?(1.0)` is true) and
# `equal?` compares identity (two equal strings or arrays are still
# different objects). A survivor means no test separates value equality from
# the stricter forms, so the comparison in use is never pinned down.
#
# Comparisons against nil, true, false or a symbol literal are skipped: those
# are singletons, so all three forms always agree.
class Evilution::Mutator::Operator::InequalityToNegatedIdentity < Evilution::Mutator::Base
  SELECTORS = %i[eql? equal?].freeze
  private_constant :SELECTORS

  SINGLETON_LITERALS = [Prism::NilNode, Prism::TrueNode, Prism::FalseNode, Prism::SymbolNode].freeze
  private_constant :SINGLETON_LITERALS

  def visit_call_node(node)
    rewrite(node) if node.name == :!=
    super
  end

  private

  def rewrite(node)
    return unless node.arguments in Prism::ArgumentsNode[arguments: [argument]]
    return if [node.receiver, argument].any? { |operand| singleton_literal?(operand) }

    left = receiver_source(node.receiver)
    SELECTORS.each do |selector|
      add_mutation(offset: node.start_offset, length: node.location.length,
                   replacement: "!#{left}.#{selector}(#{source_of(argument)})", node: node)
    end
  end

  def singleton_literal?(operand)
    SINGLETON_LITERALS.any? { |type| operand.is_a?(type) }
  end
end
