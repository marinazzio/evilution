# frozen_string_literal: true

require "json"
require "securerandom"
require "time"
require "fileutils"

module Evilution
  module Session
    class Store
      DEFAULT_DIR = ".evilution/results"

      def initialize(results_dir: DEFAULT_DIR)
        @results_dir = results_dir
      end

      def save(summary)
        FileUtils.mkdir_p(@results_dir)

        now = Time.now
        data = build_session_data(summary, now)
        filename = "#{format_timestamp(now)}-#{SecureRandom.hex(4)}.json"
        path = File.join(@results_dir, filename)
        atomic_write(path, ::JSON.pretty_generate(data))
        path
      end

      def list
        return [] unless Dir.exist?(@results_dir)

        Dir.glob(File.join(@results_dir, "*.json"))
           .sort_by { |f| File.basename(f) }
           .reverse
           .filter_map { |f| build_list_entry(f) }
      end

      def load(path)
        raise Evilution::Error, "session file not found: #{path}" unless File.exist?(path)

        ::JSON.parse(File.read(path))
      end

      private

      def build_session_data(summary, now)
        {
          version: Evilution::VERSION,
          timestamp: now.iso8601,
          git: git_context,
          summary: build_summary(summary),
          survived: summary.survived_results.map { |r| build_mutation_detail(r) },
          killed_count: summary.killed,
          timed_out_count: summary.timed_out,
          error_count: summary.errors,
          neutral_count: summary.neutral,
          equivalent_count: summary.equivalent
        }
      end

      def build_summary(summary)
        {
          total: summary.total,
          killed: summary.killed,
          survived: summary.survived,
          timed_out: summary.timed_out,
          errors: summary.errors,
          neutral: summary.neutral,
          equivalent: summary.equivalent,
          score: summary.score.round(4),
          duration: summary.duration.round(4)
        }
      end

      def build_mutation_detail(result)
        mutation = result.mutation
        {
          operator: mutation.operator_name,
          file: mutation.file_path,
          line: mutation.line,
          subject: mutation.subject.name,
          diff: mutation.diff
        }
      end

      def git_context
        sha = `git rev-parse HEAD 2>/dev/null`.strip
        branch = `git rev-parse --abbrev-ref HEAD 2>/dev/null`.strip
        {
          sha: sha.empty? ? nil : sha,
          branch: branch.empty? ? nil : branch
        }
      end

      def format_timestamp(time)
        time.strftime("%Y%m%dT%H%M%S")
      end

      def atomic_write(path, content)
        temp_path = "#{path}.tmp-#{Process.pid}-#{SecureRandom.hex(4)}"
        File.write(temp_path, content)
        File.rename(temp_path, path)
      rescue StandardError
        FileUtils.rm_f(temp_path)
        raise
      end

      def build_list_entry(file)
        data = ::JSON.parse(File.read(file))
        summary = data["summary"]
        return nil unless data.is_a?(Hash) && summary.is_a?(Hash)

        {
          file: file,
          timestamp: data["timestamp"],
          total: summary["total"],
          killed: summary["killed"],
          survived: summary["survived"],
          score: summary["score"],
          duration: summary["duration"]
        }
      rescue ::JSON::ParserError, SystemCallError
        nil
      end
    end
  end
end
