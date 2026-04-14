# frozen_string_literal: true

require_relative "../commands"
require_relative "../command"
require_relative "../dispatcher"
require_relative "../printers/tests_list"
require_relative "../../config"
require_relative "../../spec_resolver"
require_relative "../../git/changed_files"

class Evilution::CLI::Commands::TestsList < Evilution::CLI::Command
  private

  def perform
    config = Evilution::Config.new(target_files: @files, line_ranges: @line_ranges, **@options)

    if config.spec_files.any?
      Evilution::CLI::Printers::TestsList.new(mode: :explicit, specs: config.spec_files).render(@stdout)
      return 0
    end

    source_files = resolve_source_files(config)
    if source_files.empty?
      @stdout.puts("No source files found")
      return 0
    end

    resolver = Evilution::SpecResolver.new
    entries = source_files.map { |source| { source: source, spec: resolver.call(source) } }
    Evilution::CLI::Printers::TestsList.new(mode: :resolved, entries: entries).render(@stdout)
    0
  end

  def resolve_source_files(config)
    return config.target_files unless config.target_files.empty?

    Evilution::Git::ChangedFiles.new.call
  rescue Evilution::Error
    []
  end
end

Evilution::CLI::Dispatcher.register(:tests_list, Evilution::CLI::Commands::TestsList)
