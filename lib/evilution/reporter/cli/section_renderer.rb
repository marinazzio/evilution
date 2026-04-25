# frozen_string_literal: true

require_relative "../cli"

class Evilution::Reporter::CLI::SectionRenderer
  def call(section, summary)
    items = section.fetcher.call(summary)
    return [] if items.empty?

    title = section.title.respond_to?(:call) ? section.title.call(items) : section.title
    lines = ["", title]
    items.each { |item| lines << section.formatter.format(item) }
    lines
  end
end
