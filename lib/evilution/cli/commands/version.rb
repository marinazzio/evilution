# frozen_string_literal: true

require_relative "../commands"
require_relative "../command"
require_relative "../dispatcher"
require_relative "../../version"

class Evilution::CLI::Commands::Version < Evilution::CLI::Command
  private

  def perform
    @stdout.puts(Evilution::VERSION)
    0
  end
end

Evilution::CLI::Dispatcher.register(:version, Evilution::CLI::Commands::Version)
