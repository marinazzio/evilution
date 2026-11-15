# frozen_string_literal: true

require_relative "../line_formatters"

# The mutations each skip_sites preset left out, under the mutation count
# whose "skipped" figure they are part of.
class Evilution::Reporter::CLI::LineFormatters::SkippedSites
  def format(summary)
    sites = summary.skipped_sites
    return nil if sites.empty?

    "Skipped sites: #{sites.map { |name, count| "#{name} #{count}" }.join(", ")}"
  end
end
