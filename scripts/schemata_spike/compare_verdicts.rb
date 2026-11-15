# frozen_string_literal: true

# usage: ruby compare_verdicts.rb <a.json> <b.json>
# Matches the mutants of two evilution JSON reports by file, line, operator
# and diff, and prints how many match and the first entries whose status
# differs.
require "json"

STATUSES = %w[killed survived timed_out errors neutral equivalent unresolved unparseable uncovered].freeze

def statuses(path)
  report = JSON.parse(File.read(path))
  STATUSES.flat_map do |status|
    (report[status] || []).map { |r| [[r["file"], r["line"], r["operator"], r["diff"]], status] }
  end.to_h
end

a = statuses(ARGV[0])
b = statuses(ARGV[1])
differing = a.keys.reject { |k| a[k] == b[k] }
puts "matched=#{(a.keys & b.keys).size} only_a=#{(a.keys - b.keys).size} only_b=#{(b.keys - a.keys).size} " \
     "differing=#{differing.size}"
differing.first(20).each { |k| puts "#{a[k]} -> #{b[k]}  #{k[0]}:#{k[1]} #{k[2]}\n#{k[3]}" }
