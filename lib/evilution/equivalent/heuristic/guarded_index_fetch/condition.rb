# frozen_string_literal: true

require_relative "../guarded_index_fetch"

# Whether a condition, when truthy, says the read's key is there.
#
# That is the read itself, `recv[key].present?`, `recv.dig(key)`, or a key
# predicate on the same receiver and key -- alone or as one side of an `&&`,
# since both sides hold when the whole does. `refutes?` answers the mirror
# question, for conditions that are truthy when the key is missing.
class Evilution::Equivalent::Heuristic::GuardedIndexFetch::Condition
  KEY_PREDICATES = %i[key? has_key? include? member?].freeze
  SINGLE_KEY_LOOKUPS = (KEY_PREDICATES + [:dig]).freeze
  ABSENCE_TESTS = %i[nil? blank?].freeze

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

  # Whether a condition, when falsy, says the read's key is there: the
  # negation of something that proves it, `recv[key].nil?` / `.blank?`, or
  # either as one side of an `||`, since both sides are falsy when the whole
  # is. This is what an early exit tests: `return if config[:k].nil?`.
  def refutes?(node)
    case node
    when Prism::ParenthesesNode then single_statement(node) { |inner| refutes?(inner) }
    when Prism::OrNode then refutes?(node.left) || refutes?(node.right)
    when Prism::CallNode then read_absent?(node)
    else false
    end
  end

  private

  def parenthesized?(node)
    single_statement(node) { |inner| proves?(inner) }
  end

  def single_statement(node)
    body = node.body
    body.is_a?(Prism::StatementsNode) && body.body.length == 1 && yield(body.body.first)
  end

  # `!cond` and `not cond` are both a call to `!`.
  def read_absent?(call)
    return proves?(call.receiver) if call.name == :!

    ABSENCE_TESTS.include?(call.name) && @read.same?(call.receiver)
  end

  def read_present?(call)
    return true if @read.same?(call)
    return @read.same?(call.receiver) if call.name == :present? && call.arguments.nil?

    SINGLE_KEY_LOOKUPS.include?(call.name) && @read.on_receiver?(call) && @read.keyed?(call)
  end
end
