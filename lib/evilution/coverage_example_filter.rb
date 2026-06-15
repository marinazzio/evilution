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
#   - F built and L covered by examples -> run exactly the covering examples.
#     These come from the WHOLE suite, so they include cross-file killers the
#     path-resolver never selected; spec_paths is only a hint for the fallback.
#   - F built, L attributed to no example, but L DID execute (e.g. a `def` line
#     covered at load) -> an example may still exercise it indirectly, so fall
#     back to lexical rather than risk losing a kill.
#   - F built and L never executed at all -> a true coverage gap: no example can
#     kill it, so return nil (the mutation is marked :unresolved, zero runs).
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
    return nil unless @map.executed?(file, mutation.line)

    @lexical.call(mutation, spec_paths)
  end
end
