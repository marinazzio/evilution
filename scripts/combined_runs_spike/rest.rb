# frozen_string_literal: true

# rest.rb <control.json> <combined.json>
# The mutants not handled in groups: their cost in the control and in the
# combined run.
require_relative "results"

control = SpikeResults.rows(ARGV.fetch(0))
combined = SpikeResults.rows(ARGV.fetch(1))
members = SpikeResults.stats(ARGV.fetch(1))["outcomes"].flat_map { |o| o["members"] }.to_set

def cost(control, combined, keys)
  "control dur=#{SpikeResults.sum(control, keys, "duration").round(1)} " \
    "ex=#{SpikeResults.sum(control, keys, "examples_run").to_i} | " \
    "combined dur=#{SpikeResults.sum(combined, keys, "duration").round(1)} " \
    "ex=#{SpikeResults.sum(combined, keys, "examples_run").to_i}"
end

non_group = combined.keys.reject { |k| members.include?(k) }
puts "non-group mutations=#{non_group.size}: #{cost(control, combined, non_group)}"
fallbacks = combined.keys.select { |k| members.include?(k) && !SpikeResults.combined?(combined[k]) }
puts "group fallbacks=#{fallbacks.size}: #{cost(control, combined, fallbacks)}"
non_group_killed = non_group.select { |k| control[k]["status"] == "killed" }
puts "non-group killed=#{non_group_killed.size}: #{cost(control, combined, non_group_killed)}"
