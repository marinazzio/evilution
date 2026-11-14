# frozen_string_literal: true

require_relative "../cli"
require_relative "result"
require_relative "../git/since_scope"

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

  # The file arguments and their line ranges, limited with --since REF to the
  # lines changed since that ref.
  def scoped_paths
    Evilution::Git::SinceScope.apply(@options[:since], files: @files, line_ranges: @line_ranges)
  end

  def build_operator_options(config)
    { skip_heredoc_literals: config.skip_heredoc_literals? }
  end

  def build_subject_filter(config)
    require_relative "../ast/skip_filter"
    Evilution::AST::SkipFilter.for(config)
  end
end
