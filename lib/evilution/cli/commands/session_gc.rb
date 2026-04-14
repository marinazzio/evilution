# frozen_string_literal: true

require_relative "../commands"
require_relative "../command"
require_relative "../dispatcher"
require_relative "../../session/store"

class Evilution::CLI::Commands::SessionGc < Evilution::CLI::Command
  private

  def perform
    raise Evilution::ConfigError, "--older-than is required for session gc" unless @options[:older_than]

    cutoff = parse_duration(@options[:older_than])
    store_opts = {}
    store_opts[:results_dir] = @options[:results_dir] if @options[:results_dir]
    store = Evilution::Session::Store.new(**store_opts)
    deleted = store.gc(older_than: cutoff)

    if deleted.empty?
      @stdout.puts("No sessions to delete")
    else
      @stdout.puts("Deleted #{deleted.length} session#{"s" unless deleted.length == 1}")
    end

    0
  end

  def parse_duration(value)
    match = value.match(/\A(\d+)([dhw])\z/)
    unless match
      raise Evilution::ConfigError,
            "invalid --older-than format: #{value.inspect}. Use Nd, Nh, or Nw (e.g., 30d)"
    end

    amount = match[1].to_i
    seconds = case match[2]
              when "h" then amount * 3600
              when "d" then amount * 86_400
              when "w" then amount * 604_800
              end
    Time.now - seconds
  end
end

Evilution::CLI::Dispatcher.register(:session_gc, Evilution::CLI::Commands::SessionGc)
