# frozen_string_literal: true

require_relative "parsed_args"

class Evilution::CLI::Parser
  def initialize(argv, stdin: $stdin)
    @argv = argv.dup
    @stdin = stdin
    @options = {}
    @files = []
    @line_ranges = {}
    @command = :run
    @parse_error = nil
    @stdin_error = nil
  end

  def parse
    extract_command
    return build_parsed_args if @command == :parse_error

    preprocess_flags
    remaining = OptionsBuilder.build(@options).parse!(@argv)
    parsed_paths = FileArgs.parse(remaining)
    @files = parsed_paths.files
    @line_ranges = parsed_paths.ranges
    read_stdin_files if @options.delete(:stdin) && %i[run subjects].include?(@command)
    build_parsed_args
  end

  private

  def extract_command
    result = CommandExtractor.call(@argv)
    @command = result.command
    @argv = result.remaining_argv
    @parse_error = result.parse_error
  end

  def preprocess_flags
    result = []
    i = 0
    i = consume_token(i, result) while i < @argv.length
    @argv = result
  end

  def consume_token(i, result)
    arg = @argv[i]
    next_arg = @argv[i + 1]
    if arg == "--fail-fast" && !next_arg.nil? && next_arg.match?(/\A-?\d+\z/)
      @options[:fail_fast] = next_arg
      return i + 2
    end
    if arg.start_with?("--fail-fast=")
      @options[:fail_fast] = arg.delete_prefix("--fail-fast=")
      return i + 1
    end
    result << arg
    i + 1
  end

  def read_stdin_files
    result = StdinReader.call(@stdin, existing_files: @files)
    if result.error
      @stdin_error = result.error
      return
    end
    @files = result.files
    @line_ranges = @line_ranges.merge(result.ranges)
  end

  def build_parsed_args
    Evilution::CLI::ParsedArgs.new(
      command: @command,
      options: @options,
      files: @files,
      line_ranges: @line_ranges,
      stdin_error: @stdin_error,
      parse_error: @parse_error
    )
  end
end

require_relative "parser/command_extractor"
require_relative "parser/file_args"
require_relative "parser/stdin_reader"
require_relative "parser/options_builder"
