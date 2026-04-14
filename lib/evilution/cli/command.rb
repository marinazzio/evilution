# frozen_string_literal: true

require_relative "result"

class Evilution::CLI::Command
  def initialize(parsed_args, stdout: $stdout, stderr: $stderr)
    @options = parsed_args.options
    @files = parsed_args.files
    @line_ranges = parsed_args.line_ranges
    @stdin_error = parsed_args.stdin_error
    @stdout = stdout
    @stderr = stderr
  end

  def call
    Evilution::CLI::Result.new(exit_code: perform)
  rescue Evilution::Error => e
    Evilution::CLI::Result.new(exit_code: 2, error: e)
  end

  private

  def perform
    raise NotImplementedError
  end

  def build_operator_options(config)
    { skip_heredoc_literals: config.skip_heredoc_literals? }
  end

  def build_subject_filter(config)
    return nil if config.ignore_patterns.empty?

    require_relative "../ast/pattern/filter"
    Evilution::AST::Pattern::Filter.new(config.ignore_patterns)
  end
end
