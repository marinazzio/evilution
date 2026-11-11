# frozen_string_literal: true

require "time"
require_relative "comparison"
require_relative "format"

# Renders samples ({target => {version => VersionSample}}) as markdown.
class BenchmarkPerf::Report
  include BenchmarkPerf::Format

  OPERATOR_ROWS = 15
  OPERATOR_NOTE = "Operator rows are shares of killtime (sum of per-mutation durations); " \
                  "with --jobs > 1 they do not add up to Δwall."
  VERSION_HEADER = ["version", "wall median [min–max] s", "mutants", "wall/mutant s", "killtime/mutant s", "killtime s",
                    "duration s", "statuses", "unstable", "failed runs", "phases"].freeze
  TOTALS_HEADER = ["version", "wall s", "mutants", "Δwall s", "count effect s", "cost effect s", "lost kills"].freeze

  def initialize(versions:, version_labels:, samples:, repeats:, generated_at: Time.now)
    @versions = versions
    @labels = version_labels
    @samples = samples
    @repeats = repeats
    @generated_at = generated_at
  end

  def to_markdown
    sections = [header]
    @samples.each { |target, by_version| sections << target_section(target, by_version) }
    sections << totals
    "#{sections.join("\n\n")}\n"
  end

  private

  def baseline
    @versions.first
  end

  def others
    @versions.drop(1)
  end

  def header
    lines = ["# Evilution perf benchmark", "",
             "Generated #{@generated_at.iso8601}, #{@repeats} repeat(s) per version, versions interleaved.", ""]
    @versions.each do |ref|
      marker = ref == baseline ? " (baseline)" : ""
      lines << "- `#{ref}` — #{@labels.fetch(ref, ref)}#{marker}"
    end
    lines.join("\n")
  end

  def target_section(target, by_version)
    parts = ["## #{target}", table(VERSION_HEADER, @versions.map { |ref| version_cells(ref, by_version.fetch(ref)) })]
    others.each do |ref|
      comparison = BenchmarkPerf::Comparison.new(base: by_version.fetch(baseline), other: by_version.fetch(ref))
      parts << comparison_block(ref, comparison)
      parts << operator_block(ref, comparison) if comparison.available?
    end
    parts.join("\n\n")
  end

  def version_cells(ref, sample)
    return failed_cells(ref, sample) if sample.failed?

    [ref, wall_range(sample), sample.mutant_count, *per_mutant_cells(sample), num(sample.killtime_median),
     num(sample.duration_median), status_list(sample), sample.unstable_count, sample.failed_count,
     sample.phases || "—"]
  end

  def wall_range(sample)
    "#{num(sample.wall_median)} [#{num(sample.wall_min)}–#{num(sample.wall_max)}]"
  end

  def failed_cells(ref, sample)
    [ref, "FAILED: #{cell(sample.errors.first)}", *Array.new(7, ""), sample.failed_count, "—"]
  end

  def per_mutant_cells(sample)
    [per_mutant(sample.wall_median, sample), per_mutant(sample.killtime_median, sample)]
  end

  def per_mutant(total, sample)
    sample.mutant_count.zero? ? "n/a" : num(total / sample.mutant_count, 3)
  end

  def cell(text)
    text.to_s.gsub("|", "\\|")
  end

  def status_list(sample)
    sample.status_counts.sort.map { |status, count| "#{status} #{count}" }.join(", ")
  end

  def comparison_block(ref, comparison)
    title = "### #{ref} vs #{baseline}"
    return "#{title}\n\nn/a (failed run)" unless comparison.available?

    lines = [title, "", *delta_lines(comparison), "- Common mutants: #{comparison.common_count}"]
    lines.concat(key_list("Lost kills", comparison.lost_kills))
    lines.concat(key_list("Killed → timed out", comparison.flips_to_timeout))
    lines.join("\n")
  end

  def delta_lines(comparison)
    noise = comparison.noise? ? " (noise)" : ""
    ["- Δwall: #{signed(comparison.delta_wall)} s (#{percent(comparison)})#{noise}",
     "- Count effect: #{signed(comparison.count_effect)} s; cost effect: #{signed(comparison.cost_effect)} s"]
  end

  def percent(comparison)
    base_wall = comparison.base_wall
    return "n/a" if base_wall.zero?

    format("%+.1f%%", comparison.delta_wall * 100.0 / base_wall)
  end

  def key_list(title, keys)
    ["- #{title}: #{keys.size}", *keys.map { |key| "  - `#{key}`" }]
  end

  def operator_block(ref, comparison)
    header = ["operator", "state", "count #{baseline}", "count #{ref}", "killtime #{baseline} s",
              "killtime #{ref} s", "count effect s", "cost effect s"]
    rows = comparison.operator_rows.first(OPERATOR_ROWS).map { |row| operator_cells(row) }
    "#{table(header, rows)}\n\n#{OPERATOR_NOTE}"
  end

  def operator_cells(row)
    [row.operator, row.state, row.base_count, row.other_count, num(row.base_duration),
     num(row.other_duration), signed(row.count_effect), signed(row.cost_effect)]
  end

  def totals
    text = "## Totals\n\n#{table(TOTALS_HEADER, @versions.map { |ref| totals_cells(ref) })}"
    excluded = excluded_targets
    excluded.empty? ? text : "#{text}\n\nExcluded from totals: #{excluded.join(", ")}"
  end

  # Totals compare like with like: only targets every version finished.
  def complete_targets
    @samples.reject { |_, by_version| @versions.any? { |ref| by_version.fetch(ref).failed? } }
  end

  def excluded_targets
    (@samples.keys - complete_targets.keys).map do |target|
      failed = @versions.select { |ref| @samples.fetch(target).fetch(ref).failed? }
      "#{target} (#{failed.join(", ")} failed)"
    end
  end

  def totals_cells(ref)
    samples = complete_targets.values.map { |by_version| by_version.fetch(ref) }
    cells = [ref, num(samples.sum(&:wall_median)), samples.sum(&:mutant_count)]
    ref == baseline ? cells + ["", "", "", ""] : cells + delta_totals(available_comparisons(ref))
  end

  def delta_totals(comparisons)
    [signed(sum_of(comparisons, :delta_wall)), signed(sum_of(comparisons, :count_effect)),
     signed(sum_of(comparisons, :cost_effect)), comparisons.sum { |c| c.lost_kills.size }]
  end

  def available_comparisons(ref)
    complete_targets.values.map do |by_version|
      BenchmarkPerf::Comparison.new(base: by_version.fetch(baseline), other: by_version.fetch(ref))
    end.select(&:available?)
  end

  def sum_of(comparisons, reader)
    values = comparisons.map(&reader).compact
    values.empty? ? nil : values.sum
  end
end
