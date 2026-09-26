# frozen_string_literal: true

require_relative "../operator"

# Turn a proc into a lambda: `proc { |a, b| ... }` and `Proc.new { ... }`
# become `lambda { ... }`, with the block itself untouched.
#
# A lambda checks arity (wrong argument counts raise ArgumentError instead
# of padding with nil or dropping extras), does not auto-splat a single
# array argument, and `return` inside it returns from the lambda rather than
# from the enclosing method. A survivor means no test relies on any of that.
#
# Only a literal block with no arguments qualifies: `proc(&blk)` and
# `Proc.new(x) { }` are skipped.
class Evilution::Mutator::Operator::ProcToLambda < Evilution::Mutator::Base
  def visit_call_node(node)
    rewrite(node) if proc_constructor?(node) && node.block.is_a?(Prism::BlockNode) && node.arguments.nil?
    super
  end

  private

  def proc_constructor?(node)
    case node.name
    when :proc then node.receiver.nil?
    when :new then proc_constant?(node.receiver)
    end
  end

  def proc_constant?(receiver)
    case receiver
    when Prism::ConstantReadNode then receiver.name == :Proc
    when Prism::ConstantPathNode then receiver.parent.nil? && receiver.name == :Proc
    end
  end

  # Replace the call head — `proc`, `Proc.new` or `Proc.new()` — leaving the
  # block in place.
  def rewrite(node)
    head_end = (node.closing_loc || node.message_loc).end_offset
    add_mutation(offset: node.start_offset, length: head_end - node.start_offset, replacement: "lambda", node: node)
  end
end
