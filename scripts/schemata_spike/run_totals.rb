# frozen_string_literal: true

# usage: ruby run_totals.rb <report.json>...
# Per run: duration, killtime and the summed per-mutation apply / test_run /
# confirmation timings of an evilution JSON report.
require "json"

STATUSES = %w[killed survived timed_out errors neutral equivalent].freeze

ARGV.each do |path|
  report = JSON.parse(File.read(path))
  rows = STATUSES.flat_map { |k| report[k] || [] }
  total = ->(key) { rows.sum { |r| (r["timings"] || {})[key] || 0 } }
  summary = report["summary"]
  printf("%<file>-22s n=%<n>4d dur=%<dur>6.2f kill=%<kill>6.2f apply=%<apply>6.2f test_run=%<test_run>6.2f conf=%<conf>5.2f\n",
         file: File.basename(path), n: summary["total"], dur: summary["duration"].to_f, kill: summary["killtime"].to_f,
         apply: total["apply"], test_run: total["test_run"], conf: total["confirmation"])
end
