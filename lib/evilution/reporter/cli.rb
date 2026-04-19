# frozen_string_literal: true

require_relative "../reporter"

class Evilution::Reporter::CLI
  SEPARATOR = "=" * 44

  def call(summary)
    lines = []
    lines << header
    lines << SEPARATOR
    lines << ""
    lines << mutations_line(summary)
    lines << score_line(summary)
    lines << duration_line(summary)
    lines << efficiency_line(summary) if summary.duration.positive?
    peak = summary.peak_memory_mb
    lines << peak_memory_line(peak) if peak
    append_survived(lines, summary)
    append_neutral(lines, summary)
    append_equivalent(lines, summary)
    append_unresolved(lines, summary)
    append_errors(lines, summary)
    append_disabled(lines, summary)
    lines << ""
    lines << "[TRUNCATED] Stopped early due to --fail-fast" if summary.truncated?
    lines << result_line(summary)

    lines.join("\n")
  end

  private

  def append_survived(lines, summary)
    gaps = summary.coverage_gaps
    return unless gaps.any?

    lines << ""
    lines << "Survived mutations (#{gaps.length} coverage gap#{"s" unless gaps.length == 1}):"
    gaps.each { |gap| lines << format_coverage_gap(gap) }
  end

  def append_neutral(lines, summary)
    return unless summary.neutral_results.any?

    lines << ""
    lines << "Neutral mutations (test already failing):"
    summary.neutral_results.each { |result| lines << format_neutral(result) }
  end

  def append_equivalent(lines, summary)
    return unless summary.equivalent_results.any?

    lines << ""
    lines << "Equivalent mutations (provably identical behavior):"
    summary.equivalent_results.each { |result| lines << format_neutral(result) }
  end

  def append_unresolved(lines, summary)
    return unless summary.unresolved_results.any?

    lines << ""
    lines << "Unresolved mutations (no test file resolved):"
    summary.unresolved_results.each { |result| lines << format_neutral(result) }
  end

  def append_errors(lines, summary)
    errored = summary.results.select(&:error?)
    return if errored.empty?

    lines << ""
    lines << "Errored mutations:"
    errored.each { |result| lines << format_error(result) }
  end

  def format_error(result)
    mutation = result.mutation
    header = "  #{mutation.operator_name}: #{mutation.file_path}:#{mutation.line}"
    return header unless result.error_message

    indented = result.error_message.lines.map { |line| "    #{line.chomp}" }.join("\n")
    "#{header}\n#{indented}"
  end

  def append_disabled(lines, summary)
    return unless summary.disabled_mutations.any?

    lines << ""
    lines << "Disabled mutations (skipped by # evilution:disable):"
    summary.disabled_mutations.each { |mutation| lines << format_disabled(mutation) }
  end

  def header
    "Evilution v#{Evilution::VERSION} — Mutation Testing Results"
  end

  def mutations_line(summary)
    parts = "Mutations: #{summary.total} total, #{summary.killed} killed, " \
            "#{summary.survived} survived, #{summary.timed_out} timed out"
    parts += ", #{summary.neutral} neutral" if summary.neutral.positive?
    parts += ", #{summary.equivalent} equivalent" if summary.equivalent.positive?
    parts += ", #{summary.unresolved} unresolved" if summary.unresolved.positive?
    parts += ", #{summary.skipped} skipped" if summary.skipped.positive?
    parts
  end

  def score_line(summary)
    score_pct = format_pct(summary.score)
    "Score: #{score_pct} (#{summary.killed}/#{summary.score_denominator})"
  end

  def duration_line(summary)
    "Duration: #{format("%.2f", summary.duration)}s"
  end

  def efficiency_line(summary)
    pct = format("%.2f%%", summary.efficiency * 100)
    rate = format("%.2f", summary.mutations_per_second)
    "Efficiency: #{pct} killtime, #{rate} mutations/s"
  end

  def format_coverage_gap(gap)
    location = "#{gap.file_path}:#{gap.line}"
    header = if gap.single?
               "  #{gap.primary_operator}: #{location} (#{gap.subject_name})"
             else
               operators = gap.operator_names.join(", ")
               "  #{location} (#{gap.subject_name}) [#{gap.count} mutations: #{operators}]"
             end
    body = gap.mutation_results.first.mutation.unified_diff || gap.primary_diff
    indented = body.split("\n").map { |l| "    #{l}" }.join("\n")
    "#{header}\n#{indented}"
  end

  def format_neutral(result)
    mutation = result.mutation
    "  #{mutation.operator_name}: #{mutation.file_path}:#{mutation.line}"
  end

  def format_disabled(mutation)
    "  #{mutation.operator_name}: #{mutation.file_path}:#{mutation.line}"
  end

  def result_line(summary)
    min_score = 0.8
    pass_fail = summary.success?(min_score: min_score) ? "PASS" : "FAIL"
    score_pct = format_pct(summary.score)
    threshold_pct = format_pct(min_score)
    "Result: #{pass_fail} (score #{score_pct} #{pass_fail == "PASS" ? ">=" : "<"} #{threshold_pct})"
  end

  def peak_memory_line(peak_mb)
    format("Peak memory: %<mb>.1f MB", mb: peak_mb)
  end

  def format_pct(value)
    format("%.2f%%", value * 100)
  end
end
