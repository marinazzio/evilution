# frozen_string_literal: true

class Evilution::CLI::Parser::CommandExtractor
  SIMPLE_COMMANDS = {
    "version" => :version,
    "init" => :init,
    "mcp" => :mcp,
    "subjects" => :subjects,
    "compare" => :compare
  }.freeze

  SESSION_SUBCOMMANDS = {
    "list" => :session_list,
    "show" => :session_show,
    "diff" => :session_diff,
    "gc" => :session_gc
  }.freeze

  TESTS_SUBCOMMANDS = { "list" => :tests_list }.freeze
  ENVIRONMENT_SUBCOMMANDS = { "show" => :environment_show }.freeze
  UTIL_SUBCOMMANDS = { "mutation" => :util_mutation }.freeze

  Result = Struct.new(:command, :remaining_argv, :parse_error)

  def self.call(argv)
    new(argv).call
  end

  def initialize(argv)
    @argv = argv.dup
    @command = :run
    @parse_error = nil
  end

  def call
    extract
    Result.new(@command, @argv, @parse_error)
  end

  private

  def extract
    first = @argv.first
    if SIMPLE_COMMANDS.key?(first)
      @command = SIMPLE_COMMANDS[first]
      @argv.shift
    elsif first == "run"
      @argv.shift
    elsif first == "session"
      @argv.shift
      extract_subcommand(SESSION_SUBCOMMANDS, "session", "list, show, diff, gc")
    elsif first == "tests"
      @argv.shift
      extract_subcommand(TESTS_SUBCOMMANDS, "tests", "list")
    elsif first == "environment"
      @argv.shift
      extract_subcommand(ENVIRONMENT_SUBCOMMANDS, "environment", "show")
    elsif first == "util"
      @argv.shift
      extract_subcommand(UTIL_SUBCOMMANDS, "util", "mutation")
    end
  end

  def extract_subcommand(table, family, available)
    sub = @argv.first
    if table.key?(sub)
      @command = table[sub]
      @argv.shift
    elsif sub.nil?
      @command = :parse_error
      @parse_error = "Missing #{family} subcommand. Available subcommands: #{available}"
    else
      @command = :parse_error
      @parse_error = "Unknown #{family} subcommand: #{sub}. Available subcommands: #{available}"
      @argv.shift
    end
  end
end
