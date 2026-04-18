# frozen_string_literal: true

require_relative "../mutate_tool"

module Evilution::MCP::MutateTool::OptionParser
  VALID_VERBOSITIES = %w[full summary minimal].freeze
  PASSTHROUGH_KEYS = %i[target timeout jobs fail_fast suggest_tests incremental integration
                        isolation baseline save_session].freeze
  ALLOWED_OPT_KEYS = (PASSTHROUGH_KEYS + %i[spec skip_config]).freeze

  def self.parse_files(raw_files)
    files = []
    ranges = {}

    raw_files.each do |arg|
      file, range_str = arg.split(":", 2)
      files << file
      next unless range_str

      ranges[file] = parse_line_range(range_str)
    end

    [files, ranges]
  end

  def self.parse_line_range(str)
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

  def self.normalize_verbosity(value)
    normalized = value.to_s.strip.downcase
    normalized = "summary" if normalized.empty?
    return normalized if VALID_VERBOSITIES.include?(normalized)

    raise Evilution::ParseError, "invalid verbosity: #{value.inspect} (must be full, summary, or minimal)"
  end

  def self.validate!(opts)
    unknown = opts.keys - ALLOWED_OPT_KEYS
    return if unknown.empty?

    raise Evilution::ParseError, "unknown parameters: #{unknown.join(", ")}"
  end
end
