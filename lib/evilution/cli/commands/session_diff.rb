# frozen_string_literal: true

require "json"
require_relative "../commands"
require_relative "../command"
require_relative "../dispatcher"
require_relative "../printers/session_diff"
require_relative "../../session/store"
require_relative "../../session/diff"

class Evilution::CLI::Commands::SessionDiff < Evilution::CLI::Command
  private

  def perform
    raise Evilution::ConfigError, "two session file paths required" unless @files.length == 2

    store = Evilution::Session::Store.new
    base_data = store.load(@files[0])
    head_data = store.load(@files[1])
    result = Evilution::Session::Diff.new.call(base_data, head_data)
    Evilution::CLI::Printers::SessionDiff.new(result, format: @options[:format]).render(@stdout)
    0
  rescue ::JSON::ParserError => e
    raise Evilution::Error, "invalid session file: #{e.message}"
  rescue SystemCallError => e
    raise Evilution::Error, e.message
  end
end

Evilution::CLI::Dispatcher.register(:session_diff, Evilution::CLI::Commands::SessionDiff)
