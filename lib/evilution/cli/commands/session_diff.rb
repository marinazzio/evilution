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

    result = compute_diff(@files)
    Evilution::CLI::Printers::SessionDiff.new(result, format: @options[:format]).render(@stdout)
    0
  rescue ::JSON::ParserError => e
    raise Evilution::Error, "invalid session file: #{e.message}"
  rescue SystemCallError => e
    raise Evilution::Error, e.message
  end

  def compute_diff(files)
    store = Evilution::Session::Store.new
    Evilution::Session::Diff.new.call(store.load(files[0]), store.load(files[1]))
  end
end

Evilution::CLI::Dispatcher.register(:session_diff, Evilution::CLI::Commands::SessionDiff)
