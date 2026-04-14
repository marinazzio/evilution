# frozen_string_literal: true

require "json"
require_relative "../printers"

class Evilution::CLI::Printers::SessionDiff
  def initialize(result, format:)
    @result = result
    @format = format
  end

  def render(io)
    @format == :json ? render_json(io) : render_text(io)
  end

  private

  def render_json(io)
    io.puts(JSON.pretty_generate(@result.to_h))
  end

  def render_text(io)
    print_summary(io, @result.summary)
    print_section(io, "Fixed (survived \u2192 killed)", @result.fixed, "\e[32m")
    print_section(io, "New survivors (killed \u2192 survived)", @result.new_survivors, "\e[31m")
    print_section(io, "Persistent survivors", @result.persistent, "\e[33m")

    return unless @result.fixed.empty? && @result.new_survivors.empty? && @result.persistent.empty?

    io.puts("")
    io.puts("No mutation changes between sessions")
  end

  def print_summary(io, summary)
    delta_str = format("%+.2f%%", summary.score_delta * 100)
    io.puts("Session Diff")
    io.puts("=" * 40)
    io.puts(format("Base score:  %<score>6.2f%%  (%<killed>d/%<total>d killed)",
                   score: summary.base_score * 100, killed: summary.base_killed,
                   total: summary.base_total))
    io.puts(format("Head score:  %<score>6.2f%%  (%<killed>d/%<total>d killed)",
                   score: summary.head_score * 100, killed: summary.head_killed,
                   total: summary.head_total))
    io.puts("Delta:       #{delta_str}")
  end

  def print_section(io, title, mutations, color)
    return if mutations.empty?

    reset = "\e[0m"
    io.puts("")
    io.puts("#{color}#{title} (#{mutations.length}):#{reset}")
    mutations.each do |m|
      io.puts("  #{m["operator"]} \u2014 #{m["file"]}:#{m["line"]}  #{m["subject"]}")
    end
  end
end
