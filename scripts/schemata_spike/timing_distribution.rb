# frozen_string_literal: true

# usage: ruby timing_distribution.rb <report.json>
# Per-mutant distribution of apply, test_run, duration and isolation overhead
# (duration minus apply, test_run and confirmation) in one JSON report.
require "json"

report = JSON.parse(File.read(ARGV[0]))
rows = %w[killed survived timed_out errors neutral equivalent].flat_map { |k| report[k] || [] }
timing = ->(key) { rows.map { |r| r.dig("timings", key) }.compact.sort }
quantile = ->(a, p) { a[(a.size * p).floor.clamp(0, a.size - 1)] }
describe = lambda do |a|
  next "-" if a.empty?

  ms = ->(v) { v * 1000 }
  format("n=%<n>d mean=%<mean>.2fms p10=%<p10>.2f p50=%<p50>.2f p90=%<p90>.2f max=%<max>.2f",
         n: a.size, mean: ms[a.sum / a.size], p10: ms[quantile[a, 0.1]], p50: ms[quantile[a, 0.5]],
         p90: ms[quantile[a, 0.9]], max: ms[a.max])
end
isolation = rows.map do |r|
  t = r["timings"] || {}
  r["duration"] - %w[apply test_run confirmation].sum { |k| t[k] || 0 }
end.sort

puts "apply     #{describe[timing["apply"]]}"
puts "test_run  #{describe[timing["test_run"]]}"
puts "duration  #{describe[rows.map { |r| r["duration"] }.compact.sort]}"
puts "isolation #{describe[isolation]}"
