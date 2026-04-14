# frozen_string_literal: true

require "json"
require_relative "../printers"

class Evilution::CLI::Printers::SessionDetail
  def initialize(data, format:)
    @data = data
    @format = format
  end

  def render(io)
    @format == :json ? render_json(io) : render_text(io)
  end

  private

  def render_json(io)
    io.puts(JSON.pretty_generate(@data))
  end

  def render_text(io)
    print_header(io, @data)
    print_summary(io, @data["summary"])
    print_survived(io, @data["survived"] || [])
  end

  def print_header(io, data)
    io.puts("Session: #{data["timestamp"]}")
    io.puts("Version: #{data["version"]}")
    print_git_context(io, data["git"])
  end

  def print_git_context(io, git)
    return unless git.is_a?(Hash)

    branch = git["branch"]
    sha = git["sha"]
    return if branch.to_s.empty? && sha.to_s.empty?

    io.puts("Git:     #{branch} (#{sha})")
  end

  def print_summary(io, summary)
    io.puts("")
    io.puts(
      format(
        "Score: %<score>.2f%%  Total: %<total>d  Killed: %<killed>d  Survived: %<surv>d  " \
        "Timed out: %<to>d  Errors: %<err>d  Duration: %<dur>.1fs",
        score: summary["score"] * 100, total: summary["total"], killed: summary["killed"],
        surv: summary["survived"], to: summary["timed_out"], err: summary["errors"],
        dur: summary["duration"]
      )
    )
  end

  def print_survived(io, survived)
    io.puts("")
    if survived.empty?
      io.puts("No survived mutations")
    else
      io.puts("Survived mutations (#{survived.length}):")
      survived.each_with_index { |m, i| print_mutation_detail(io, m, i + 1) }
    end
  end

  def print_mutation_detail(io, mutation, index)
    io.puts("")
    io.puts("  #{index}. #{mutation["operator"]} — #{mutation["file"]}:#{mutation["line"]}")
    io.puts("     Subject: #{mutation["subject"]}")
    return unless mutation["diff"]

    io.puts("     Diff:")
    mutation["diff"].each_line { |line| io.puts("       #{line.chomp}") }
  end
end
