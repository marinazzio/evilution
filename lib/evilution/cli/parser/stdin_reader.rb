# frozen_string_literal: true

require_relative "file_args"

class Evilution::CLI::Parser::StdinReader
  Result = Struct.new(:files, :ranges, :error)

  def self.call(io, existing_files:)
    new(io, existing_files: existing_files).call
  end

  def initialize(io, existing_files:)
    @io = io
    @existing_files = existing_files
  end

  def call
    return Result.new([], {}, "--stdin cannot be combined with positional file arguments") if @existing_files.any?

    lines = []
    @io.each_line do |line|
      line = line.strip
      lines << line unless line.empty?
    end
    files, ranges = Evilution::CLI::Parser::FileArgs.parse(lines)
    Result.new(files, ranges, nil)
  end
end
