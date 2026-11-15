# frozen_string_literal: true

# sum.rb <run.json>...
# One line per run: the summary counts and, for a combined run, the group stats.
require_relative "results"

def group_stats(path)
  stats_file = SpikeResults.stats_path(path)
  return "" unless File.exist?(stats_file)

  st = JSON.parse(File.read(stats_file))
  return "" unless st["group_runs"]

  errors = st["outcomes"].filter_map { |o| o["error"] }.tally
  " groups=#{st["group_runs"]} killed_in_groups=#{st["killed_in_groups"]} rest=#{st["rest_mutations"]} " \
    "gphase=#{st["group_phase_seconds"].round(1)} rphase=#{st["rest_phase_seconds"].round(1)} gerr=#{errors}"
end

ARGV.each do |path|
  s = JSON.parse(File.read(path))["summary"]
  puts "#{File.basename(path)}: total=#{s["total"]} k=#{s["killed"]} s=#{s["survived"]} to=#{s["timed_out"]} " \
       "e=#{s["errors"]} n=#{s["neutral"]} unc=#{s["uncovered"]} dur=#{s["duration"]} " \
       "kt=#{s["killtime"]}#{group_stats(path)}"
end
