# frozen_string_literal: true

require_relative "run_result"

# Markdown and number formatting shared by the report sections.
module BenchmarkPerf::Format
  def table(header, rows)
    lines = [row(header), row(Array.new(header.size, "---"))]
    lines.concat(rows.map { |cells| row(cells) })
    lines.join("\n")
  end

  def row(cells)
    "| #{cells.join(" | ")} |"
  end

  def num(value, digits = 1)
    value.nil? ? "n/a" : format("%.#{digits}f", value)
  end

  def signed(value)
    value.nil? ? "n/a" : format("%+.1f", value)
  end
end
