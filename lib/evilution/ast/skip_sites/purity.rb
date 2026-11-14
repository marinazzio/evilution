# frozen_string_literal: true

require "prism"
require_relative "../skip_sites"

# Whether evaluating an expression only reads: a mutation inside it can then
# change the value it builds, and nothing else. Literals, variable and
# constant reads, interpolation and the control flow between them read; so
# does a call that takes no arguments and no block and whose name does not
# end in `!` (an attribute reader, `inspect`, `class`, unary minus), and the
# few calls that only compute a value whatever their name or arguments (`!`,
# binary operators, `[]`, `format`, `join`, `to_s(base)`). Anything else --
# a call with arguments or a block, an assignment, `yield`, a backtick --
# may change state, and mutating it could change more than a message.
module Evilution::AST::SkipSites::Purity
  READS = [
    Prism::StringNode, Prism::InterpolatedStringNode, Prism::EmbeddedStatementsNode, Prism::EmbeddedVariableNode,
    Prism::SymbolNode, Prism::InterpolatedSymbolNode, Prism::RegularExpressionNode,
    Prism::IntegerNode, Prism::FloatNode, Prism::RationalNode, Prism::ImaginaryNode,
    Prism::NilNode, Prism::TrueNode, Prism::FalseNode, Prism::SelfNode,
    Prism::SourceFileNode, Prism::SourceLineNode, Prism::SourceEncodingNode,
    Prism::LocalVariableReadNode, Prism::InstanceVariableReadNode, Prism::ClassVariableReadNode,
    Prism::GlobalVariableReadNode, Prism::BackReferenceReadNode, Prism::NumberedReferenceReadNode,
    Prism::ConstantReadNode, Prism::ConstantPathNode,
    Prism::ArgumentsNode, Prism::StatementsNode, Prism::ParenthesesNode,
    Prism::ArrayNode, Prism::HashNode, Prism::KeywordHashNode, Prism::AssocNode, Prism::RangeNode,
    Prism::AndNode, Prism::OrNode, Prism::IfNode, Prism::UnlessNode, Prism::ElseNode, Prism::DefinedNode,
    Prism::BlockNode, Prism::BlockParametersNode, Prism::ParametersNode, Prism::RequiredParameterNode
  ].freeze

  COMPUTING_CALLS = %i[
    [] + - * / % ** == != < > <= >= <=> ! to_s join format sprintf
  ].freeze

  private_constant :READS, :COMPUTING_CALLS

  module_function

  def pure?(root)
    pending = [root]
    until pending.empty?
      node = pending.pop
      return false unless reads?(node)

      pending.concat(node.compact_child_nodes)
    end
    true
  end

  def reads?(node)
    return reading_call?(node) if node.is_a?(Prism::CallNode)

    READS.any? { |type| node.is_a?(type) }
  end

  # A block, even `&:sym`, runs code the call decides when to run.
  def reading_call?(call)
    return false if call.block

    name = call.name
    COMPUTING_CALLS.include?(name) || (call.arguments.nil? && !name.end_with?("!"))
  end
end
