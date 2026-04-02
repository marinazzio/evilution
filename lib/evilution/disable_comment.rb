# frozen_string_literal: true

require "prism"

class Evilution::DisableComment
  DISABLE_PATTERN = /\A[^"']*#\s*evilution:disable\s*$/
  ENABLE_PATTERN = /\A[^"']*#\s*evilution:enable\s*$/
  STANDALONE_DISABLE_PATTERN = /\A\s*#\s*evilution:disable\s*$/

  def call(source)
    return [] if source.empty?

    lines = source.lines
    method_ranges = extract_method_ranges(source)
    scan_lines(lines, method_ranges)
  end

  private

  def scan_lines(lines, method_ranges)
    disabled = []
    range_start = nil

    lines.each_with_index do |line, index|
      line_number = index + 1

      if line.match?(ENABLE_PATTERN) && range_start
        disabled << (range_start..line_number)
        range_start = nil
      elsif line.match?(DISABLE_PATTERN)
        range_start = process_disable(line, line_number, method_ranges, disabled)
      end
    end

    disabled << (range_start..lines.length) if range_start

    disabled
  end

  def process_disable(line, line_number, method_ranges, disabled)
    unless line.match?(STANDALONE_DISABLE_PATTERN)
      disabled << (line_number..line_number)
      return nil
    end

    method_range = find_method_range(method_ranges, line_number + 1)
    if method_range
      disabled << (line_number..method_range.last)
      nil
    else
      line_number
    end
  end

  def extract_method_ranges(source)
    result = Prism.parse(source)
    return [] if result.failure?

    ranges = []
    collect_def_ranges(result.value, ranges)
    ranges
  end

  def collect_def_ranges(node, ranges)
    if node.is_a?(Prism::DefNode)
      loc = node.location
      ranges << (loc.start_line..loc.end_line)
    end

    node.child_nodes.each do |child|
      collect_def_ranges(child, ranges) if child
    end
  end

  def find_method_range(method_ranges, def_line)
    method_ranges.find { |range| range.first == def_line }
  end
end
