# frozen_string_literal: true

require "json"
require_relative "../printers"

class Evilution::CLI::Printers::SessionList
  def initialize(sessions, format:)
    @sessions = sessions
    @format = format
  end

  def render(io)
    @format == :json ? render_json(io) : render_text(io)
  end

  private

  def render_json(io)
    io.puts(JSON.pretty_generate(@sessions.map { |s| session_to_hash(s) }))
  end

  def render_text(io)
    header = "Timestamp                       Total Killed  Surv.    Score Duration"
    io.puts(header)
    io.puts("-" * header.length)
    @sessions.each { |s| io.puts(format_row(s)) }
  end

  def format_row(session)
    format(
      "%-30<ts>s %6<total>d %6<killed>d %6<surv>d %7.2<score>f%% %7.1<dur>fs",
      ts: session[:timestamp], total: session[:total], killed: session[:killed],
      surv: session[:survived], score: session[:score] * 100, dur: session[:duration]
    )
  end

  def session_to_hash(session)
    {
      "timestamp" => session[:timestamp],
      "total" => session[:total],
      "killed" => session[:killed],
      "survived" => session[:survived],
      "score" => session[:score],
      "duration" => session[:duration],
      "file" => session[:file]
    }
  end
end
