# frozen_string_literal: true

require "json"
require "digest"

module BenchmarkPerf
  # JSON report buckets (keys) vs the per-mutation "status" field (values):
  # timeouts sit under "timed_out" with status "timeout", errors under
  # "errors" with status "error".
  CATEGORIES = %w[killed survived neutral equivalent unresolved unparseable uncovered timed_out errors].freeze
  STATUSES = %w[killed survived timeout error neutral equivalent unresolved unparseable uncovered].freeze
  KEY_FIELDS = %w[file line operator].freeze

  class ParseError < StandardError; end

  module_function

  # File-name-safe form of a target name or git ref.
  def slug(name)
    name.gsub(/[^A-Za-z0-9._-]/, "_")
  end

  # Stable identity of a mutation across versions and repeats. Same formula as
  # scripts/compare_targeting so keys from both tools line up.
  def mutation_key(detail)
    base = KEY_FIELDS.map { |field| detail[field] }.join(":")
    diff = detail["diff"].to_s
    diff.empty? ? base : "#{base}##{Digest::SHA256.hexdigest(diff)[0, 8]}"
  end

  # Evilution prints its report as one JSON line, but stdout can carry other
  # output around it (preload chatter, SimpleCov's at_exit summary). Try the
  # whole output first, then each line that opens an object, last one first.
  def extract_json(stdout)
    whole = parse_object(stdout)
    return whole if whole

    stdout.lines.reverse_each do |line|
      next unless line.start_with?("{")

      parsed = parse_object(line)
      return parsed if parsed
    end
    raise ParseError, "no JSON report in evilution output"
  end

  def parse_object(text)
    value = JSON.parse(text)
    value.is_a?(Hash) ? value : nil
  rescue JSON::ParserError
    nil
  end

  # One evilution run of one version on one target.
  class RunResult
    attr_reader :wall, :duration, :killtime, :statuses, :operators, :status_counts, :phases, :error

    def self.from_json(data, wall:)
      summary = data["summary"] || {}
      details = collect_details(data)
      new(
        wall: wall,
        duration: summary.fetch("duration", 0.0).to_f,
        killtime: summary.fetch("killtime", 0.0).to_f,
        statuses: details.transform_values { |d| d["status"] },
        operators: operator_totals(details.values)
      )
    end

    def self.failed(error, wall:)
      new(wall: wall, duration: 0.0, killtime: 0.0, statuses: {}, operators: {}, error: error)
    end

    def self.collect_details(data)
      CATEGORIES.each_with_object({}) do |category, by_key|
        Array(data[category]).each { |detail| by_key[BenchmarkPerf.mutation_key(detail)] ||= detail }
      end
    end

    def self.operator_totals(details)
      details.each_with_object({}) do |detail, totals|
        entry = totals[detail["operator"]] ||= { count: 0, duration: 0.0 }
        entry[:count] += 1
        entry[:duration] += detail["duration"].to_f
      end
    end

    private_class_method :collect_details, :operator_totals

    def initialize(wall:, duration:, killtime:, statuses:, operators:, error: nil)
      @wall = wall
      @duration = duration
      @killtime = killtime
      @statuses = statuses.freeze
      @operators = operators.freeze
      @status_counts = statuses.values.tally.freeze
      @phases = nil
      @error = error
      freeze
    end

    def mutant_count
      statuses.size
    end

    def failed?
      !error.nil?
    end
  end
end
