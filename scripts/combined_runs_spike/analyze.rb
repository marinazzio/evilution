# frozen_string_literal: true

# analyze.rb <control.json> <combined.json>
# Cost of the group phase against the same mutants' single runs.
require_relative "results"

control = SpikeResults.rows(ARGV.fetch(0))
combined = SpikeResults.rows(ARGV.fetch(1))
outcomes = SpikeResults.stats(ARGV.fetch(1))["outcomes"]
members = outcomes.flat_map { |o| o["members"] }
killed_in_group = combined.select { |_k, r| SpikeResults.combined?(r) }.keys
fell_back = members - killed_in_group
fallback_status = fell_back.map { |k| control[k] && control[k]["status"] }.tally

puts "group members=#{members.size} killed_in_group=#{killed_in_group.size} " \
     "fell_back=#{fell_back.size} (control status of fallbacks: #{fallback_status})"
puts "control cost of killed_in_group: duration=#{SpikeResults.sum(control, killed_in_group, "duration").round(1)} " \
     "examples=#{SpikeResults.sum(control, killed_in_group, "examples_run").to_i}"
puts "control cost of fell_back:       duration=#{SpikeResults.sum(control, fell_back, "duration").round(1)}"
puts "group runs: n=#{outcomes.size} duration=#{outcomes.sum { |o| o["duration"] }.round(1)} " \
     "examples=#{outcomes.sum { |o| o["examples_run"].to_i }}"
puts "fallback single runs (combined run): duration=#{SpikeResults.sum(combined, fell_back, "duration").round(1)}"
control_processes = control.values.count { |r| SpikeResults.ran?(r) }
single_processes = combined.values.count { |r| SpikeResults.ran?(r) && !SpikeResults.combined?(r) }
puts "processes: control=#{control_processes} combined=#{outcomes.size + single_processes}"
