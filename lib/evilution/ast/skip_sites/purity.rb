# frozen_string_literal: true

require "prism"
require_relative "../skip_sites"

# Whether evaluating an expression only reads: a mutation inside it can then
# change the value it builds, and nothing else. Literals, variable and
# constant reads, interpolation and the control flow between them read; so
# do the calls known to only compute a value: operators, `[]`, `format`,
# `join`, `to_s(base)` whatever their arguments, and, without arguments or a
# block, predicates (`empty?`) and common readers (`id`, `name`, `message`,
# `inspect`, `size`, `to_i`). A call's name alone says nothing of what it
# does -- `queue.pop`, `io.read`, `enum.next` change state -- so any other
# call, an assignment, `yield`, a backtick may change state, and mutating it
# could change more than a message.
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

  READERS = %i[
    -@ +@ ~ class name message full_message inspect to_str to_sym to_i to_f to_a to_h id object_id hash
    size length count first last keys values key value path basename dirname extname upcase downcase strip itself
  ].freeze

  private_constant :READS, :COMPUTING_CALLS, :READERS

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
    COMPUTING_CALLS.include?(name) || (call.arguments.nil? && (READERS.include?(name) || name.end_with?("?")))
  end
end
