# frozen_string_literal: true

require_relative "../commands"
require_relative "../command"
require_relative "../dispatcher"
require_relative "../printers/environment"
require_relative "../../config"

class Evilution::CLI::Commands::EnvironmentShow < Evilution::CLI::Command
  private

  def perform
    config = Evilution::Config.new(**@options)
    config_file = Evilution::Config::CONFIG_FILES.find { |path| File.exist?(path) }
    Evilution::CLI::Printers::Environment.new(config, config_file: config_file).render(@stdout)
    0
  end
end

Evilution::CLI::Dispatcher.register(:environment_show, Evilution::CLI::Commands::EnvironmentShow)
