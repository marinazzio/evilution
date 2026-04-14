# frozen_string_literal: true

require "tempfile"
require "prism"
require_relative "../commands"
require_relative "../command"
require_relative "../dispatcher"
require_relative "../printers/util_mutation"
require_relative "../../config"
require_relative "../../mutator/registry"
require_relative "../../ast/parser"

class Evilution::CLI::Commands::UtilMutation < Evilution::CLI::Command
  private

  def perform
    source, file_path = resolve_util_mutation_source
    subjects = parse_source_to_subjects(source, file_path)
    config = Evilution::Config.new(**@options)
    registry = Evilution::Mutator::Registry.default
    operator_options = build_operator_options(config)
    mutations = subjects.flat_map { |s| registry.mutations_for(s, operator_options: operator_options) }

    if mutations.empty?
      @stdout.puts("No mutations generated")
      return 0
    end

    Evilution::CLI::Printers::UtilMutation.new(mutations, format: @options[:format]).render(@stdout)
    0
  ensure
    @util_tmpfile.close! if @util_tmpfile
  end

  def resolve_util_mutation_source
    if @options[:eval]
      tmpfile = Tempfile.new(["evilution_eval", ".rb"])
      tmpfile.write(@options[:eval])
      tmpfile.flush
      @util_tmpfile = tmpfile
      [@options[:eval], tmpfile.path]
    elsif @files.first
      path = @files.first
      raise Evilution::Error, "file not found: #{path}" unless File.exist?(path)

      begin
        [File.read(path), path]
      rescue SystemCallError => e
        raise Evilution::Error, e.message
      end
    else
      raise Evilution::Error, "source required: use -e 'code' or provide a file path"
    end
  end

  def parse_source_to_subjects(source, file_label)
    result = Prism.parse(source)
    raise Evilution::Error, "failed to parse source: #{result.errors.map(&:message).join(", ")}" if result.failure?

    finder = Evilution::AST::SubjectFinder.new(source, file_label)
    finder.visit(result.value)
    finder.subjects
  end
end

Evilution::CLI::Dispatcher.register(:util_mutation, Evilution::CLI::Commands::UtilMutation)
