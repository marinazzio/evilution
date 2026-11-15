# frozen_string_literal: true

# ideal.rb <control.json> <stats.json>
# Process count per cap if every group ran cleanly and only the members the
# control did not kill fell back to a single run.
require_relative "results"

control = SpikeResults.rows(ARGV.fetch(0))
stats = JSON.parse(File.read(ARGV.fetch(1)))
ran = control.values.count { |r| SpikeResults.ran?(r) }
puts "control processes=#{ran} mutants=#{control.size}"
stats["caps"].each do |cap, value|
  groups = value["plan"].select { |g| g.size > 1 }
  members = groups.flatten(1)
  fallback = members.count { |k| control[k] && control[k]["status"] != "killed" }
  processes = ran - members.size + groups.size + fallback
  mean = (members.size.to_f / [groups.size, 1].max).round(1)
  change = ((processes - ran) * 100.0 / ran).round(1)
  puts "cap #{cap}: groups=#{groups.size} members=#{members.size} mean=#{mean} " \
       "fallback=#{fallback} processes=#{processes} (#{change}%)"
end
