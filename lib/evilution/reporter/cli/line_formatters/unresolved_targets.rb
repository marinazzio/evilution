# frozen_string_literal: true

require_relative "../line_formatters"

# EV-p4sm / GH #1603: a target file that resolves to no test file contributes
# only a handful of `unresolved` mutations, which UnresolvedRateWarning dilutes
# against every other file in the run — 14 unresolved out of 98 sits under its
# threshold and says nothing at all. This formatter reports the stronger,
# per-file fact instead, and names the files so the reader knows which of the
# paths they passed was never tested.
class Evilution::Reporter::CLI::LineFormatters::UnresolvedTargets
  def format(summary)
    return nil unless summary.unresolved_targets?

    files = summary.unresolved_target_files
    listing = files.map { |path| "    #{path}" }.join("\n")
    "! #{headline(files.length, summary.target_file_count)}:\n#{listing}"
  end

  private

  # The ratio is dropped rather than guessed when the run's target count is
  # unknown, which is how a summary restored from a saved session arrives. The
  # noun agrees with whichever number it follows ("1 of 2 target files has",
  # "1 target file has"), the verb with how many were unresolved.
  def headline(unresolved_count, target_file_count)
    noun_count = target_file_count.nil? ? unresolved_count : target_file_count
    noun = noun_count == 1 ? "target file" : "target files"
    verb = unresolved_count == 1 ? "has" : "have"
    tail = unresolved_count == 1 ? "it was never tested" : "they were never tested"
    scope = target_file_count.nil? ? unresolved_count.to_s : "#{unresolved_count} of #{target_file_count}"

    "#{scope} #{noun} #{verb} no resolvable spec — #{tail}"
  end
end
