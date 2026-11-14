# frozen_string_literal: true

require "prism"
require_relative "../skip_sites"
require_relative "nodes"
require_relative "message"

# The message of a raised error. The raise itself, the class raised and the
# condition guarding the raise decide behaviour and are never covered.
#
# A site is `raise` or `fail` sent to no receiver or to Kernel. Its message
# is the second positional argument (`raise Error, "msg"`), or the only one
# when that is a string (`raise "msg"`); when the error is built in place
# (`raise Error.new("msg")`, `.exception`, on a constant), its string
# arguments are messages, while its other arguments may be data the error
# keeps. Keywords (`cause:`) and the backtrace argument are not messages; a
# splat leaves the positions unknown, and nothing is covered.
#
# A mutation inside a message is skipped when it changes the message alone:
# literal text of the message, or anything inside a message that only reads
# (see Purity). In `"left: #{queue.pop!}"` the text is covered and the call
# is not.
class Evilution::AST::SkipSites::ErrorMessages
  RAISES = %i[raise fail].freeze
  CONSTRUCTORS = %i[new exception].freeze
  private_constant :RAISES, :CONSTRUCTORS

  def name
    :error_messages
  end

  # chain: the mutated node, then its ancestors, nearest first.
  def covers?(chain)
    chain.each_with_index.any? do |node, index|
      Evilution::AST::SkipSites::Nodes.kernel_call?(node, RAISES) &&
        Evilution::AST::SkipSites::Message.covered_in(chain, index, messages(node))
    end
  end

  private

  def messages(raise_call)
    positional = Evilution::AST::SkipSites::Nodes.positional_arguments(raise_call)
    return [] if positional.nil?
    return [positional[1]] if positional.length > 1

    only = positional.first
    return [only] if Evilution::AST::SkipSites::Nodes.string?(only)

    constructed_messages(only)
  end

  def constructed_messages(node)
    return [] unless constructor_call?(node)

    positional = Evilution::AST::SkipSites::Nodes.positional_arguments(node) || []
    positional.select { |argument| Evilution::AST::SkipSites::Nodes.string?(argument) }
  end

  def constructor_call?(node)
    node.is_a?(Prism::CallNode) && CONSTRUCTORS.include?(node.name) &&
      (node.receiver.is_a?(Prism::ConstantReadNode) || node.receiver.is_a?(Prism::ConstantPathNode))
  end
end
