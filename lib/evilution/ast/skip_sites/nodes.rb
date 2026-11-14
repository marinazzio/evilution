# frozen_string_literal: true

require "prism"
require_relative "../skip_sites"

# Questions the presets ask of single nodes.
module Evilution::AST::SkipSites::Nodes
  SIGILS = /\A(?:@@|@|\$)/
  private_constant :SIGILS

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
end
