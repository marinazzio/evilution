# frozen_string_literal: true

require "prism"

class Evilution::AST::SorbetSigDetector
  def call(source)
    return [] if source.empty?

    result = Prism.parse(source)
    return [] if result.failure?

    ranges = []
    collect_sig_ranges(result.value, ranges, :byte)
    ranges
  end

  def line_ranges(source)
    return [] if source.empty?

    result = Prism.parse(source)
    return [] if result.failure?

    ranges = []
    collect_sig_ranges(result.value, ranges, :line)
    ranges
  end

  private

  def collect_sig_ranges(node, ranges, mode)
    if sig_block?(node)
      loc = node.location
      ranges << if mode == :byte
                  (loc.start_offset...loc.end_offset)
                else
                  (loc.start_line..loc.end_line)
                end
    end

    node.child_nodes.each do |child|
      collect_sig_ranges(child, ranges, mode) if child
    end
  end

  def sig_block?(node)
    node.is_a?(Prism::CallNode) &&
      node.name == :sig &&
      node.receiver.nil? &&
      node.arguments.nil? &&
      !node.block.nil?
  end
end
