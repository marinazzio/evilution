# frozen_string_literal: true

require "prism"

class Evilution::DisableComment
  DISABLE_MARKER = /\A#\s*evilution:disable\s*\z/
  ENABLE_MARKER = /\A#\s*evilution:enable\s*\z/

  def call(source)
    return [] if source.empty?

    result = Prism.parse(source)
    return [] if result.failure?

    method_ranges = collect_def_ranges(result.value)
    comments = classify_comments(result, source)
    scan_comments(comments, method_ranges, source.lines.length)
  end

  private

  def classify_comments(parse_result, source)
    parse_result.comments.filter_map do |comment|
      loc = comment.location
      text = source.byteslice(loc.start_offset, loc.end_offset - loc.start_offset)
                   .force_encoding(source.encoding)

      if text.match?(DISABLE_MARKER)
        line = source.lines[loc.start_line - 1]
        standalone = line.strip == text.strip
        { type: :disable, line: loc.start_line, standalone: standalone }
      elsif text.match?(ENABLE_MARKER)
        { type: :enable, line: loc.start_line }
      end
    end
  end

  def scan_comments(comments, method_ranges, total_lines)
    disabled = []
    range_start = nil

    comments.each do |comment|
      if comment[:type] == :enable && range_start
        disabled << (range_start..comment[:line])
        range_start = nil
      elsif comment[:type] == :disable && range_start.nil?
        range_start = process_disable(comment, method_ranges, disabled)
      end
    end

    disabled << (range_start..total_lines) if range_start

    disabled
  end

  def process_disable(comment, method_ranges, disabled)
    unless comment[:standalone]
      disabled << (comment[:line]..comment[:line])
      return nil
    end

    method_range = find_method_range(method_ranges, comment[:line] + 1)
    if method_range
      disabled << (comment[:line]..method_range.last)
      nil
    else
      comment[:line]
    end
  end

  def collect_def_ranges(node)
    ranges = []
    walk_def_nodes(node, ranges)
    ranges
  end

  def walk_def_nodes(node, ranges)
    if node.is_a?(Prism::DefNode)
      loc = node.location
      ranges << (loc.start_line..loc.end_line)
    end

    node.child_nodes.each do |child|
      walk_def_nodes(child, ranges) if child
    end
  end

  def find_method_range(method_ranges, def_line)
    method_ranges.find { |range| range.first == def_line }
  end
end
