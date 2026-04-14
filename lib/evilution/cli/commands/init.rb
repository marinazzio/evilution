# frozen_string_literal: true

require_relative "../commands"
require_relative "../command"
require_relative "../dispatcher"
require_relative "../../config"

class Evilution::CLI::Commands::Init < Evilution::CLI::Command
  private

  def perform
    path = ".evilution.yml"
    if File.exist?(path)
      @stderr.puts("#{path} already exists")
      return 1
    end

    File.write(path, Evilution::Config.default_template)
    @stdout.puts("Created #{path}")
    0
  end
end

Evilution::CLI::Dispatcher.register(:init, Evilution::CLI::Commands::Init)
