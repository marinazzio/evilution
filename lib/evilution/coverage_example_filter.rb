# frozen_string_literal: true

require_relative "../evilution"
require_relative "coverage/map"

# Per-mutation example targeting backed by a real line-coverage Map (EV-ndjd).
# Honours the same contract as the lexical Evilution::ExampleFilter --
# call(mutation, spec_paths) -> Array[location] | spec_paths | nil -- so it drops
# straight into the existing ExampleFilter seam.
#
# Resolution order for the mutated source file F at line L:
#   - F not fully built in the map (digest miss / partial build) -> delegate to
#     the lexical filter (safe fallback) with the original spec_paths.
#   - F built and L covered by examples -> run exactly those covering examples
#     (a SUBSET of what the resolved spec runs, so a strict speedup that cannot
#     lose a kill full-file would catch).
#   - F not built, or L attributed to no example -> defer to lexical/full-file.
#
# Accuracy-first: coverage ONLY narrows the example set when it positively knows
# the covering examples. It never marks a mutation :unresolved on "no coverage" --
# on real repos a line can be exercised indirectly (before(:all), load time, a
# spec the per-example diff did not attribute), and asserting a gap there loses
# kills (EV-7uui validation). When coverage has no answer, the proven lexical
# path decides.
class Evilution::CoverageExampleFilter
  def initialize(map:, lexical:, project_root: Evilution::PROJECT_ROOT)
    @map = map
    @lexical = lexical
    @project_root = project_root.to_s
  end

  def call(mutation, spec_paths)
    file = File.expand_path(mutation.file_path, @project_root)
    return @lexical.call(mutation, spec_paths) unless @map.built?(file)

    examples = @map.examples_for(file, mutation.line)
    return examples unless examples.empty?

    @lexical.call(mutation, spec_paths)
  end
end
