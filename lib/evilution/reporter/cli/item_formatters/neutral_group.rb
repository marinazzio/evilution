# frozen_string_literal: true

require_relative "../item_formatters"
require_relative "result_location"

# The neutral mutations that share one reason, under a heading naming it.
#
# "Neutral" covers a spec that was already red and a test process that died on
# infrastructure; grouping by reason is what tells the reader which of the two
# they are looking at, and what to do about it (EV-5pob / GH #1606).
class Evilution::Reporter::CLI::ItemFormatters::NeutralGroup
  UNKNOWN_REASON = "reason not recorded"

  def initialize(location: Evilution::Reporter::CLI::ItemFormatters::ResultLocation.new)
    @location = location
  end

  def format(group)
    reason, results = group
    rows = results.map { |result| "  #{@location.format(result)}" }
    ["  #{reason ? reason.to_s : UNKNOWN_REASON}:", *rows].join("\n")
  end
end
