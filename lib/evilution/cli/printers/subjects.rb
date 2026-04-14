# frozen_string_literal: true

require_relative "../printers"

class Evilution::CLI::Printers::Subjects
  def initialize(entries, total_mutations:)
    @entries = entries
    @total_mutations = total_mutations
  end

  def render(io)
    @entries.each { |entry| io.puts(format_entry(entry)) }
    io.puts("")
    io.puts(summary_line)
  end

  private

  def format_entry(entry)
    "  #{entry[:name]}  #{entry[:file_path]}:#{entry[:line_number]}  (#{mutation_label(entry[:mutation_count])})"
  end

  def mutation_label(count)
    pluralize(count, "mutation", "mutations")
  end

  def summary_line
    "#{pluralize(@entries.length, "subject", "subjects")}, " \
      "#{pluralize(@total_mutations, "mutation", "mutations")}"
  end

  def pluralize(count, singular, plural)
    "#{count} #{count == 1 ? singular : plural}"
  end
end
