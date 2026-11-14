# frozen_string_literal: true

require_relative "version"
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

  # Whether no example of these spec files, and no file load, executes any
  # line the mutation changes -- so running it could only end in a survivor.
  # The lines it changes, not the line it is reported at: a method body's
  # mutation is reported at its `def`, which runs while the file loads. Only a map built from every one of the spec files can say so;
  # anything else (a spec file the build did not run, the whole spec dir, a
  # file the map cannot vouch for) answers no and the mutation runs.
  def uncovered?(mutation, spec_paths)
    return false if spec_paths.nil?

    specs = spec_paths.map { |path| File.expand_path(path, @project_root) }
    return false unless @map.built_from?(specs)

    file = File.expand_path(mutation.file_path, @project_root)
    @map.uncovered?(file, mutation.changed_lines)
  end

  # The map is built before this filter is; the lexical filter it falls back
  # on parses lazily, and is what a forked child would otherwise fill.
  def warm(mutation, spec_paths)
    @lexical.warm(mutation, spec_paths)
  end
end
