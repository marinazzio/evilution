# frozen_string_literal: true

require_relative "../operator"

# Make the first step of a `dig` strict: `config.dig(:db, :host)` becomes
# `config.fetch(:db).dig(:host)`. The reverse of index_to_dig.
#
# `dig` returns nil when the first key is missing or holds nil; the fetch
# chain raises there instead (KeyError / IndexError, or NoMethodError on
# `nil.dig`). A survivor means no test reaches the lookup with that key
# absent.
#
# Only calls with two or more positional keys qualify; the remaining keys
# keep their original formatting.
class Evilution::Mutator::Operator::DigToFetchChain < Evilution::Mutator::Base
  NON_POSITIONAL = [Prism::SplatNode, Prism::KeywordHashNode, Prism::ForwardingArgumentsNode].freeze
  private_constant :NON_POSITIONAL

  def visit_call_node(node)
    rewrite(node) if node.name == :dig && node.receiver && node.block.nil?
    super
  end

  private

  # Replace `dig(first, ` with `fetch(first).dig(` — up to the second key —
  # keeping whatever opened the argument list (`(`, a newline, a space).
  def rewrite(node)
    return unless node.arguments in Prism::ArgumentsNode[arguments: [first, second, *]]
    return unless positional_keys?(node.arguments.arguments)

    start = node.message_loc.start_offset
    add_mutation(offset: start, length: second.start_offset - start, replacement: fetch_prefix(node, first), node: node)
  end

  def positional_keys?(keys)
    keys.none? { |key| NON_POSITIONAL.any? { |type| key.is_a?(type) } }
  end

  def fetch_prefix(node, first)
    message_end = node.message_loc.end_offset
    opener = byteslice_source(message_end, first.start_offset - message_end)
    "fetch(#{source_of(first)}).dig#{opener}"
  end
end
