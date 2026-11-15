# frozen_string_literal: true

require "prism"
require_relative "../skip_sites"

# Questions the presets ask of single nodes.
module Evilution::AST::SkipSites::Nodes
  SIGILS = /\A(?:@@|@|\$)/

  # Parents whose value is the value of the branch taken.
  PASSING_ON = [
    Prism::IfNode, Prism::UnlessNode, Prism::ElseNode, Prism::CaseNode, Prism::CaseMatchNode, Prism::WhenNode,
    Prism::InNode, Prism::BeginNode, Prism::RescueNode, Prism::ParenthesesNode
  ].freeze
  # The children of those parents that are branches, not conditions.
  BRANCHES = [
    Prism::StatementsNode, Prism::ElseNode, Prism::IfNode, Prism::UnlessNode, Prism::WhenNode, Prism::InNode,
    Prism::RescueNode
  ].freeze
  # Parents that never use the value of their statements.
  DISCARDING = [Prism::ProgramNode, Prism::EnsureNode, Prism::WhileNode, Prism::UntilNode, Prism::ForNode].freeze
  private_constant :SIGILS, :PASSING_ON, :BRANCHES, :DISCARDING

  module_function

  # Two nodes stand for the same code when they are of one type and span the
  # same bytes: the node a mutation changes comes from its subject's parse of
  # the file, its ancestors from another parse of the same source.
  def same?(node, other)
    node.instance_of?(other.class) &&
      node.location.start_offset == other.location.start_offset &&
      node.location.length == other.location.length
  end

  # A call of one of the names, sent to no receiver or to Kernel.
  def kernel_call?(node, names)
    return false unless node.is_a?(Prism::CallNode) && names.include?(node.name)

    receiver = node.receiver
    receiver.nil? || constant_named?(receiver, :Kernel)
  end

  def constant_named?(node, name)
    (node.is_a?(Prism::ConstantReadNode) || node.is_a?(Prism::ConstantPathNode)) && node.name == name
  end

  # The name a receiver goes by, without sigils: `logger`, `@logger`,
  # `$logger`, `LOGGER`, `App::LOGGER` and `Rails.logger` all go by theirs;
  # anything else (no receiver, a literal, a call with arguments) by none.
  def receiver_name(node)
    case node
    when Prism::CallNode
      node.arguments || node.block ? nil : node.name.to_s
    when Prism::LocalVariableReadNode, Prism::InstanceVariableReadNode, Prism::ClassVariableReadNode,
         Prism::GlobalVariableReadNode, Prism::ConstantReadNode, Prism::ConstantPathNode
      node.name.to_s.sub(SIGILS, "")
    end
  end

  # The positional arguments of a call: its arguments without keywords, or
  # nil when a splat or a forwarded `...` makes their positions unknown.
  def positional_arguments(call)
    arguments = call.arguments ? call.arguments.arguments : []
    positional = arguments.grep_v(Prism::KeywordHashNode)
    return nil if positional.any? { |argument| argument.is_a?(Prism::SplatNode) || argument.is_a?(Prism::ForwardingArgumentsNode) }

    positional
  end

  def string?(node)
    node.is_a?(Prism::StringNode) || node.is_a?(Prism::InterpolatedStringNode)
  end

  # chain: a node, then its ancestors, nearest first. Whether the value of
  # chain[index] goes unused: it is a statement followed by another one, or
  # the last statement of a body whose value is itself unused -- a branch of
  # a conditional or a `begin` whose value goes unused, an `ensure` clause, a
  # loop body, the top of the file. The last statement of a method or a
  # block gives the value it returns, and anything else -- an assignment, an
  # operand, an argument, a condition -- uses it. Without the ancestors
  # nothing is known, and the value counts as used.
  def value_dropped?(chain, index)
    child = chain[index]
    chain.drop(index + 1).each do |parent|
      verdict = value_dropped_in(parent, child)
      return verdict unless verdict.nil?

      child = parent
    end
    false
  end

  # true or false when the parent settles it, nil when its own value decides.
  def value_dropped_in(parent, child)
    return (same?(parent.body.last, child) ? nil : true) if parent.is_a?(Prism::StatementsNode)
    return nil if passes_on?(parent, child)

    child.is_a?(Prism::StatementsNode) && DISCARDING.any? { |type| parent.is_a?(type) }
  end

  # A condition is never of a branch's type: Ruby wants it in parentheses.
  def passes_on?(parent, child)
    PASSING_ON.any? { |type| parent.is_a?(type) } && BRANCHES.any? { |type| child.is_a?(type) }
  end
end
