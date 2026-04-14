# frozen_string_literal: true

require_relative "../commands"
require_relative "../command"
require_relative "../dispatcher"
require_relative "../printers/subjects"
require_relative "../../config"
require_relative "../../runner"
require_relative "../../mutator"

class Evilution::CLI::Commands::Subjects < Evilution::CLI::Command
  private

  def perform
    raise Evilution::ConfigError, @stdin_error if @stdin_error

    config = Evilution::Config.new(target_files: @files, line_ranges: @line_ranges, **@options)
    runner = Evilution::Runner.new(config: config)
    subjects = runner.parse_and_filter_subjects

    if subjects.empty?
      @stdout.puts("No subjects found")
      return 0
    end

    entries, total = collect_entries(subjects, config)
    Evilution::CLI::Printers::Subjects.new(entries, total_mutations: total).render(@stdout)
    0
  end

  def collect_entries(subjects, config)
    registry = Evilution::Mutator::Registry.default
    filter = build_subject_filter(config)
    operator_options = build_operator_options(config)
    entries = []
    total = 0

    subjects.each do |subj|
      count = registry.mutations_for(subj, filter: filter, operator_options: operator_options).length
      total += count
      entries << { name: subj.name, file_path: subj.file_path, line_number: subj.line_number, mutation_count: count }
    ensure
      subj.release_node!
    end

    [entries, total]
  end
end

Evilution::CLI::Dispatcher.register(:subjects, Evilution::CLI::Commands::Subjects)
