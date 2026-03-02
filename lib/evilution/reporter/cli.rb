# frozen_string_literal: true

module Evilution
  module Reporter
    class CLI
      SEPARATOR = "=" * 44

      def call(summary)
        lines = []
        lines << header
        lines << SEPARATOR
        lines << ""
        lines << mutations_line(summary)
        lines << score_line(summary)
        lines << duration_line(summary)

        if summary.survived_results.any?
          lines << ""
          lines << "Survived mutations:"
          summary.survived_results.each do |result|
            lines << format_survived(result)
          end
        end

        lines << ""
        lines << result_line(summary)

        lines.join("\n")
      end

      private

      def header
        "Evilution v#{Evilution::VERSION} — Mutation Testing Results"
      end

      def mutations_line(summary)
        "Mutations: #{summary.total} total, #{summary.killed} killed, " \
          "#{summary.survived} survived, #{summary.timed_out} timed out"
      end

      def score_line(summary)
        denominator = summary.total - summary.errors
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

      def result_line(summary)
        min_score = 0.8
        pass_fail = summary.success?(min_score: min_score) ? "PASS" : "FAIL"
        score_pct = format_pct(summary.score)
        threshold_pct = format_pct(min_score)
        "Result: #{pass_fail} (score #{score_pct} #{pass_fail == "PASS" ? ">=" : "<"} #{threshold_pct})"
      end

      def format_pct(value)
        format("%.2f%%", value * 100)
      end
    end
  end
end
