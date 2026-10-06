# frozen_string_literal: true

require_relative "../guarded_index_fetch"

# Whether a condition, when truthy, says the read's key is there.
#
# That is the read itself, `recv[key].present?`, `recv.dig(key)`, or a key
# predicate on the same receiver and key -- alone or as one side of an `&&`,
# since both sides hold when the whole does.
class Evilution::Equivalent::Heuristic::GuardedIndexFetch::Condition
  KEY_PREDICATES = %i[key? has_key? include? member?].freeze
  SINGLE_KEY_LOOKUPS = (KEY_PREDICATES + [:dig]).freeze

  def initialize(read)
    @read = read
  end

  def proves?(node)
    case node
    when Prism::ParenthesesNode then parenthesized?(node)
    when Prism::AndNode then proves?(node.left) || proves?(node.right)
    when Prism::CallNode then read_present?(node)
    else false
    end
  end

  private

  def parenthesized?(node)
    body = node.body
    body.is_a?(Prism::StatementsNode) && body.body.length == 1 && proves?(body.body.first)
  end

  def read_present?(call)
    return true if @read.same?(call)
    return @read.same?(call.receiver) if call.name == :present? && call.arguments.nil?

    SINGLE_KEY_LOOKUPS.include?(call.name) && @read.on_receiver?(call) && @read.keyed?(call)
  end
end
