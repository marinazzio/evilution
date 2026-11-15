# frozen_string_literal: true

# usage: ruby apply_prof_summary.rb <APPLY_PROF file>
# Per apply step: call count, mean / p50 / p90 ms and the GCs that ran inside.
times = Hash.new { |h, k| h[k] = [] }
gcs = Hash.new(0)
File.foreach(ARGV[0]) do |line|
  step, ms, gc = line.split("\t")
  times[step] << ms.to_f
  gcs[step] += gc.to_i
end
times.each do |step, v|
  v.sort!
  printf("%<step>-13s n=%<n>5d mean=%<mean>.2f p50=%<p50>.2f p90=%<p90>.2f gcs=%<gcs>d\n",
         step: step, n: v.size, mean: v.sum / v.size, p50: v[v.size / 2], p90: v[v.size * 9 / 10], gcs: gcs[step])
end
