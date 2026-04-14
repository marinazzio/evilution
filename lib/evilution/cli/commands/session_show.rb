# frozen_string_literal: true

require "json"
require_relative "../commands"
require_relative "../command"
require_relative "../dispatcher"
require_relative "../printers/session_detail"
require_relative "../../session/store"

class Evilution::CLI::Commands::SessionShow < Evilution::CLI::Command
  private

  def perform
    path = @files.first
    raise Evilution::ConfigError, "session file path required" unless path

    data = Evilution::Session::Store.new.load(path)
    Evilution::CLI::Printers::SessionDetail.new(data, format: @options[:format]).render(@stdout)
    0
  rescue ::JSON::ParserError => e
    raise Evilution::Error, "invalid session file: #{e.message}"
  end
end

Evilution::CLI::Dispatcher.register(:session_show, Evilution::CLI::Commands::SessionShow)
