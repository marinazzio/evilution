# frozen_string_literal: true

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
    peak = summary.peak_memory_mb
    lines << peak_memory_line(peak) if peak
    append_survived(lines, summary)
    append_neutral(lines, summary)
    append_equivalent(lines, summary)
    lines << ""
    lines << "[TRUNCATED] Stopped early due to --fail-fast" if summary.truncated?
    lines << result_line(summary)

    lines.join("\n")
  end

  private

  def append_survived(lines, summary)
    return unless summary.survived_results.any?

    lines << ""
    lines << "Survived mutations:"
    summary.survived_results.each { |result| lines << format_survived(result) }
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

  def header
    "Evilution v#{Evilution::VERSION} — Mutation Testing Results"
  end

  def mutations_line(summary)
    parts = "Mutations: #{summary.total} total, #{summary.killed} killed, " \
            "#{summary.survived} survived, #{summary.timed_out} timed out"
    parts += ", #{summary.neutral} neutral" if summary.neutral.positive?
    parts += ", #{summary.equivalent} equivalent" if summary.equivalent.positive?
    parts
  end

  def score_line(summary)
    denominator = summary.total - summary.errors - summary.neutral - summary.equivalent
    score_pct = format_pct(summary.score)
    "Score: #{score_pct} (#{summary.killed}/#{denominator})"
  end

  def duration_line(summary)
    "Duration: #{format("%.2f", summary.duration)}s"
  end

  def format_survived(result)
    mutation = result.mutation
    location = "#{mutation.file_path}:#{mutation.line}"
    diff_lines = mutation.diff.split("\n").map { |l| "    #{l}" }.join("\n")
    "  #{mutation.operator_name}: #{location}\n#{diff_lines}"
  end

  def format_neutral(result)
    mutation = result.mutation
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
