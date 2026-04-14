# frozen_string_literal: true

module Evilution::CLI::Parser::FileArgs
  module_function

  def parse(raw_args)
    files = []
    ranges = {}

    raw_args.each do |arg|
      file, range_str = arg.split(":", 2)
      files << file
      next unless range_str

      ranges[file] = parse_line_range(range_str)
    end

    [files, ranges]
  end

  def expand_spec_dir(dir)
    unless File.directory?(dir)
      warn("Error: #{dir} is not a directory")
      return []
    end

    Dir.glob(File.join(dir, "**/*_spec.rb"))
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
  end
end
