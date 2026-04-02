# frozen_string_literal: true

require "prism"

class Evilution::AST::SorbetSigDetector
  def call(source)
    return [] if source.empty?

    result = Prism.parse(source)
    return [] if result.failure?

    ranges = []
    collect_sig_ranges(result.value, ranges)
    ranges
  end

  private

  def collect_sig_ranges(node, ranges)
    if sig_block?(node)
      loc = node.location
      ranges << (loc.start_offset...loc.end_offset)
    end

    node.child_nodes.each do |child|
      collect_sig_ranges(child, ranges) if child
    end
  end

  def sig_block?(node)
    node.is_a?(Prism::CallNode) &&
      node.name == :sig &&
      node.receiver.nil? &&
      node.arguments.nil? &&
      node.block
  end
end
