# frozen_string_literal: true

require_relative "../reporter"

class Evilution::Reporter::CLI
  SEPARATOR = "=" * 44

  def initialize(
    header: LineFormatters::Header.new,
    metrics_block: MetricsBlock.new,
    section_renderer: SectionRenderer.new,
    sections: DEFAULT_SECTIONS,
    trailer: Trailer.new
  )
    @header = header
    @metrics_block = metrics_block
    @section_renderer = section_renderer
    @sections = sections
    @trailer = trailer
  end

  def call(summary)
    lines = []
    lines << @header.format(summary)
    lines << SEPARATOR
    lines << ""
    lines.concat(@metrics_block.call(summary))
    @sections.each { |section| lines.concat(@section_renderer.call(section, summary)) }
    lines << ""
    lines.concat(@trailer.call(summary))
    lines.join("\n")
  end
end

require_relative "cli/pct"
require_relative "cli/section"
require_relative "cli/section_renderer"
require_relative "cli/line_formatters/header"
require_relative "cli/line_formatters/mutations"
require_relative "cli/line_formatters/score"
require_relative "cli/line_formatters/duration"
require_relative "cli/line_formatters/efficiency"
require_relative "cli/line_formatters/peak_memory"
require_relative "cli/line_formatters/truncation_notice"
require_relative "cli/line_formatters/result_line"
require_relative "cli/line_formatters/feedback_footer"
require_relative "cli/item_formatters/coverage_gap"
require_relative "cli/item_formatters/result_location"
require_relative "cli/item_formatters/error"
require_relative "cli/item_formatters/disabled"
require_relative "cli/metrics_block"
require_relative "cli/trailer"

Evilution::Reporter::CLI.const_set(
  :DEFAULT_SECTIONS,
  [
    Evilution::Reporter::CLI::Section.new(
      title: ->(gaps) { "Survived mutations (#{gaps.length} coverage gap#{"s" unless gaps.length == 1}):" },
      fetcher: lambda(&:coverage_gaps),
      formatter: Evilution::Reporter::CLI::ItemFormatters::CoverageGap.new
    ),
    Evilution::Reporter::CLI::Section.new(
      title: "Neutral mutations (test already failing):",
      fetcher: lambda(&:neutral_results),
      formatter: Evilution::Reporter::CLI::ItemFormatters::ResultLocation.new
    ),
    Evilution::Reporter::CLI::Section.new(
      title: "Equivalent mutations (provably identical behavior):",
      fetcher: lambda(&:equivalent_results),
      formatter: Evilution::Reporter::CLI::ItemFormatters::ResultLocation.new
    ),
    Evilution::Reporter::CLI::Section.new(
      title: "Unresolved mutations (no test file resolved):",
      fetcher: lambda(&:unresolved_results),
      formatter: Evilution::Reporter::CLI::ItemFormatters::ResultLocation.new
    ),
    Evilution::Reporter::CLI::Section.new(
      title: "Unparseable mutations (mutated source did not parse):",
      fetcher: lambda(&:unparseable_results),
      formatter: Evilution::Reporter::CLI::ItemFormatters::ResultLocation.new
    ),
    Evilution::Reporter::CLI::Section.new(
      title: "Errored mutations:",
      fetcher: ->(s) { s.results.select(&:error?) },
      formatter: Evilution::Reporter::CLI::ItemFormatters::Error.new
    ),
    Evilution::Reporter::CLI::Section.new(
      title: "Disabled mutations (skipped by # evilution:disable):",
      fetcher: lambda(&:disabled_mutations),
      formatter: Evilution::Reporter::CLI::ItemFormatters::Disabled.new
    )
  ].freeze
)
