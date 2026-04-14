# frozen_string_literal: true

require "json"
require_relative "../printers"

class Evilution::CLI::Printers::UtilMutation
  def initialize(mutations, format:)
    @mutations = mutations
    @format = format
  end

  def render(io)
    @format == :json ? render_json(io) : render_text(io)
  end

  private

  def render_text(io)
    @mutations.each_with_index do |m, i|
      io.puts("#{i + 1}. #{m.operator_name} — #{m.subject.name} (line #{m.line})")
      m.diff.each_line { |line| io.puts("   #{line.chomp}") }
      io.puts("")
    end
    label = @mutations.length == 1 ? "1 mutation" : "#{@mutations.length} mutations"
    io.puts(label)
  end

  def render_json(io)
    data = @mutations.map do |m|
      { operator: m.operator_name, subject: m.subject.name,
        file: m.file_path, line: m.line, diff: m.diff }
    end
    io.puts(JSON.pretty_generate(data))
  end
end
