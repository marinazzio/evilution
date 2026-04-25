# frozen_string_literal: true

require_relative "../info_tool"

module Evilution::MCP::InfoTool::RequestParser
  module_function

  def parse_files(raw_files)
    files = []
    ranges = {}

    raw_files.each do |arg|
      file, range_str = arg.split(":", 2)
      files << file
      ranges[file] = parse_line_range(range_str) if range_str
    end

    [files, ranges]
  end

  def parse_line_range(str)
    if str.include?("-")
      start_str, end_str = str.split("-", 2)
      start_line = Integer(start_str)
      end_line = end_str.empty? ? Float::INFINITY : Integer(end_str)
      start_line..end_line
    else
      line = Integer(str)
      line..line
    end
  rescue ArgumentError, TypeError
    raise Evilution::ParseError, "invalid line range: #{str.inspect}"
  end
end
