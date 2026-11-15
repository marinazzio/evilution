# frozen_string_literal: true

require "json"
require_relative "mutant"
require_relative "../variants"

# Reads one target's files from a study directory:
#   <t>-default.json     default run (stop_on_kill): verdicts, durations
#   <t>-nostop.jsonl     kill-set hook records of the --no-stop-on-kill run
#   <t>-nostop.json      that run's report (verdicts, to compare)
#   <t>-generated.jsonl  every generated mutation before de-duplication
# and joins them by file, line, operator and diff.
class OperatorYield::Corpus
  attr_reader :target, :mutants, :summary

  def initialize(dir, target)
    @dir = dir
    @target = target
    report = JSON.parse(File.read(path("default.json")))
    @summary = report["summary"]
    kills = rows_by_key("nostop.jsonl")
    alternatives = alternatives_by_key
    @mutants = OperatorYield.entries(report).map { |m| build(m, kills[key_of(m)].shift, alternatives) }
  end

  def killed_without_set = mutants.count { |m| m.status == "killed" && m.kills.nil? }

  # Mutants whose verdict differs between the default and the kill-set run.
  def verdict_mismatches
    file = path("nostop.json")
    return 0 unless File.exist?(file)

    status = OperatorYield.entries(JSON.parse(File.read(file))).to_h { |m| [key_of(m), m["status"]] }
    mutants.count { |m| status.key?(m.key) && status[m.key] != m.status }
  end

  private

  def path(suffix) = File.join(@dir, "#{target}-#{suffix}")

  def key_of(row) = OperatorYield.key_of(row)

  def variant(row) = Variants.of(row["operator"], row["diff"])

  def rows_by_key(suffix)
    rows = Hash.new { |h, k| h[k] = [] }
    file = path(suffix)
    return rows unless File.exist?(file)

    File.foreach(file) do |line|
      row = JSON.parse(line)
      rows[key_of(row)] << row unless row["operator"] == "canary_probe"
    end
    rows
  end

  # key -> one list per generated mutation with that key, of the
  # [operator, variant] of the other mutations generating the same file
  def alternatives_by_key
    generated = rows_by_key("generated.jsonl")
    by_source = generated.values.flatten.group_by { |row| row["mutated"] }
    generated.transform_values do |rows|
      rows.map { |row| by_source[row["mutated"]].reject { |o| o.equal?(row) }.map { |o| [o["operator"], variant(o)] } }
    end
  end

  def build(entry, kill_row, alternatives)
    OperatorYield::Mutant.new(
      target:, file: entry["file"], line: entry["line"], operator: entry["operator"], variant: variant(entry),
      diff: entry["diff"], status: entry["status"], duration: entry["duration"].to_f,
      **kill_fields(kill_row), alternatives: Array(alternatives.fetch(key_of(entry), []).shift)
    )
  end

  def kill_fields(row)
    return { subject: nil, kills: nil } unless row

    { subject: row["subject"], kills: row["failed"].to_set }
  end
end
