# frozen_string_literal: true

require_relative "version"
require_relative "cli/parser"
require_relative "cli/parsed_args"
require_relative "cli/printers/subjects"
require_relative "cli/dispatcher"
require_relative "cli/commands/version"
require_relative "cli/commands/init"
require_relative "cli/commands/mcp"
require_relative "cli/commands/subjects"
require_relative "cli/commands/tests_list"
require_relative "cli/commands/environment_show"
require_relative "cli/commands/util_mutation"
require_relative "cli/commands/session_list"
require_relative "cli/commands/session_show"
require_relative "cli/commands/session_diff"
require_relative "cli/commands/session_gc"
require_relative "cli/commands/compare"
require_relative "cli/commands/run"

class Evilution::CLI
  def initialize(argv, stdin: $stdin)
    parsed = Parser.new(argv, stdin: stdin).parse
    @parsed = parsed
    @command = parsed.command
    @options = parsed.options
    @files = parsed.files
    @line_ranges = parsed.line_ranges
    @stdin_error = parsed.stdin_error
    @parse_error = parsed.parse_error
  end

  def call
    return run_subcommand_error(@parse_error) if @command == :parse_error

    result = Dispatcher.lookup(@command).new(@parsed, stdout: $stdout, stderr: $stderr).call
    warn("Error: #{result.error.message}") if result.error && !result.error_rendered
    result.exit_code
  end

  private

  def run_subcommand_error(message)
    warn("Error: #{message}")
    2
  end
end
