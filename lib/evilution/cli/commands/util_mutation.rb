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
  SourceInput = Data.define(:source, :file_path)
  private_constant :SourceInput

  private

  def perform
    input = resolve_util_mutation_source
    subjects = parse_source_to_subjects(input.source, input.file_path)
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
    return build_eval_source(@options[:eval]) if @options[:eval]
    return build_file_source(@files.first) if @files.first

    raise Evilution::Error, "source required: use -e 'code' or provide a file path"
  end

  def build_eval_source(code)
    tmpfile = Tempfile.new(["evilution_eval", ".rb"])
    tmpfile.write(code)
    tmpfile.flush
    @util_tmpfile = tmpfile
    SourceInput.new(source: code, file_path: tmpfile.path)
  end

  def build_file_source(path)
    raise Evilution::Error, "file not found: #{path}" unless File.exist?(path)

    SourceInput.new(source: File.read(path), file_path: path)
  rescue SystemCallError => e
    raise Evilution::Error, e.message
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
