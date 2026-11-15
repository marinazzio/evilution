# frozen_string_literal: true

require_relative "mutant"

# Markdown output helpers.
module OperatorYield::Markdown
  module_function

  def pct(num, den) = den.zero? ? "–" : format("%.1f%%", 100.0 * num / den)

  def seconds(value) = format("%.1f", value)

  def heading(out, title) = out.puts("\n### #{title}\n\n")

  def table(out, header, rows)
    out.puts "| #{header.join(" | ")} |"
    out.puts "| --- |#{" ---: |" * (header.size - 1)}"
    rows.each { |r| out.puts "| #{r.join(" | ")} |" }
  end
end
