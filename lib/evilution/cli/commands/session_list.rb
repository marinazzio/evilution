# frozen_string_literal: true

require "time"
require_relative "../commands"
require_relative "../command"
require_relative "../dispatcher"
require_relative "../printers/session_list"
require_relative "../../session/store"

class Evilution::CLI::Commands::SessionList < Evilution::CLI::Command
  private

  def perform
    store_opts = {}
    store_opts[:results_dir] = @options[:results_dir] if @options[:results_dir]
    store = Evilution::Session::Store.new(**store_opts)
    sessions = filter_sessions(store.list)

    if sessions.empty?
      @stdout.puts("No sessions found")
      return 0
    end

    Evilution::CLI::Printers::SessionList.new(sessions, format: @options[:format]).render(@stdout)
    0
  end

  def filter_sessions(sessions)
    if @options[:since]
      cutoff = parse_date(@options[:since])
      sessions = sessions.select do |s|
        ts = s[:timestamp]
        next false unless ts.is_a?(String)

        Time.parse(ts) >= cutoff
      rescue ArgumentError
        false
      end
    end
    sessions = sessions.first(@options[:limit]) if @options[:limit]
    sessions
  end

  def parse_date(value)
    Time.parse(value)
  rescue ArgumentError
    raise Evilution::ConfigError, "invalid --since date: #{value.inspect}. Use YYYY-MM-DD format"
  end
end

Evilution::CLI::Dispatcher.register(:session_list, Evilution::CLI::Commands::SessionList)
