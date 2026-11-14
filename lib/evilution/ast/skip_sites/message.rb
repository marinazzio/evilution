# frozen_string_literal: true

require "prism"
require_relative "../skip_sites"
require_relative "nodes"
require_relative "purity"

# Where a mutation sits relative to the parts of a site that only make up a
# message (a log line's arguments, a raised error's message).
module Evilution::AST::SkipSites::Message
  module_function

  # chain: the mutated node, then its ancestors, nearest first; the site is
  # chain[site_index]. nil when the node lies in none of the parts. Otherwise
  # whether mutating it changes the message alone: it is literal text of the
  # message, outside any interpolated code, or the part it lies in only
  # reads (see Purity).
  def covered_in(chain, site_index, parts)
    index = (0...site_index).find { |position| parts.any? { |part| Evilution::AST::SkipSites::Nodes.same?(chain[position], part) } }
    return nil unless index

    literal_text?(chain, index) || Evilution::AST::SkipSites::Purity.pure?(chain[index])
  end

  # For a site whose call does nothing but report: a mutation outside every
  # part -- of the call itself, say, deleting it, or of its receiver -- is
  # covered when every part only reads, since dropping the call then drops
  # nothing but the report.
  def covered_in_call(chain, site_index, parts)
    covered = covered_in(chain, site_index, parts)
    return covered unless covered.nil?

    parts.all? { |part| Evilution::AST::SkipSites::Purity.pure?(part) }
  end

  # The text of a string, or of a string between interpolations: a mutation
  # of it changes no value but the message.
  def literal_text?(chain, part_index)
    chain.first.is_a?(Prism::StringNode) &&
      chain[1..part_index].all?(Prism::InterpolatedStringNode)
  end
end
