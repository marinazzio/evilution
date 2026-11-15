# frozen_string_literal: true

# usage: ruby gc_summary.rb <EV_GCSTAT file>...
# Per-mutant means of GC ms, GC count, major GC count and call ms.
ARGV.each do |path|
  rows = File.readlines(path).map { |l| l.split("\t").map(&:to_f) }
  n = rows.size
  gc_ms, gcs, majors, call_ms = (0..3).map { |i| rows.sum { |r| r[i] } / n }
  printf("%<file>s n=%<n>d gc_ms/mutant=%<gc_ms>.2f gcs/mutant=%<gcs>.2f major/mutant=%<majors>.3f call_ms=%<call_ms>.2f\n",
         file: File.basename(path), n: n, gc_ms: gc_ms, gcs: gcs, majors: majors, call_ms: call_ms)
end
