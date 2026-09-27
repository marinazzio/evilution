# frozen_string_literal: true

require_relative "../printers"

class Evilution::CLI::Printers::TestsList
  def initialize(mode:, specs: nil, entries: nil)
    @mode = mode
    @specs = specs
    @entries = entries
  end

  def render(io)
    case @mode
    when :explicit then render_explicit(io)
    when :resolved then render_resolved(io)
    end
  end

  private

  def render_explicit(io)
    @specs.each { |f| io.puts("  #{f}") }
    io.puts("")
    io.puts(@specs.length == 1 ? "1 spec file" : "#{@specs.length} spec files")
  end

  # Each entry is `{ source:, specs: [...] }`; a source can resolve to several
  # spec files (spec_mappings), and each gets its own line.
  def render_resolved(io)
    unique_specs = []
    @entries.each do |entry|
      source = entry[:source]
      specs = entry[:specs]
      io.puts("  #{source}  (no spec found)") if specs.empty?
      specs.each do |spec|
        unique_specs << spec
        io.puts("  #{spec}  (#{source})")
      end
    end

    unique_specs.uniq!
    io.puts("")
    spec_label = unique_specs.length == 1 ? "1 spec file" : "#{unique_specs.length} spec files"
    io.puts("#{@entries.length} source files, #{spec_label}")
  end
end
