# frozen_string_literal: true

# div.rb <control.json> <combined.json>
# Mutants whose verdict differs between the two runs, with their group context
# when the second run is a combined one (two controls compare as well).
require_relative "results"

control = SpikeResults.rows(ARGV.fetch(0))
combined = SpikeResults.rows(ARGV.fetch(1))
outcomes = Array(SpikeResults.stats(ARGV.fetch(1))["outcomes"])
where = {}
outcomes.each_with_index do |o, gi|
  o["members"].each_with_index { |m, i| where[m] = [gi, i, o] }
end

def fields(entry, names)
  entry.slice(*names).map { |name, value| "#{name}=#{value.to_s[0, 150]}" }.join(" ")
end

(control.keys & combined.keys).reject { |k| control[k]["status"] == combined[k]["status"] }.each do |k|
  gi, i, o = where[k]
  error = o && o["error"].to_s[0, 60]
  killed_in_group = o && o["killed_members"].include?(i)
  puts "#{control[k]["status"]} -> #{combined[k]["status"]} #{k[0]}:#{k[1]} #{k[2]} | " \
       "group=#{gi.inspect} err=#{error} killed_in_group=#{killed_in_group}"
  puts "   ctrl: #{fields(control[k], %w[killing_test examples_run error])}"
  puts "   comb: #{fields(combined[k], %w[killing_test examples_run error test_command])}"
end
