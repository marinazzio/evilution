# frozen_string_literal: true

require "spec_helper"
require "evilution/coverage/map"
require "evilution/coverage_example_filter"

RSpec.describe Evilution::CoverageExampleFilter do
  let(:root) { "/proj" }
  let(:source_rel) { "lib/calc.rb" }
  let(:source_abs) { "/proj/lib/calc.rb" }

  # Map built for the calc source: line 3 is covered by two examples; line 2 ran
  # (e.g. a `def` line, covered at load) but is attributed to no example; line 5
  # is a true gap (never executed). other.rb was never built.
  let(:map) do
    Evilution::Coverage::Map.new(
      index: { source_abs => { 3 => ["spec/calc_spec.rb:5", "spec/x_spec.rb:9"] } },
      built_files: [source_abs],
      executed_lines: { source_abs => [2, 3] }
    )
  end

  let(:lexical) { instance_double(Evilution::ExampleFilter) }

  subject(:filter) do
    described_class.new(map: map, lexical: lexical, project_root: root)
  end

  def mutation(file_path:, line:)
    instance_double(Evilution::Mutation, file_path: file_path, line: line)
  end

  describe "a line covered by examples (file fully built)" do
    it "returns ALL covering example locations, including cross-file ones" do
      result = filter.call(mutation(file_path: source_rel, line: 3), ["spec/calc_spec.rb"])
      expect(result).to eq(["spec/calc_spec.rb:5", "spec/x_spec.rb:9"])
    end

    it "resolves a relative mutation path against the project root to match the map" do
      result = filter.call(mutation(file_path: source_abs, line: 3), [])
      expect(result).to eq(["spec/calc_spec.rb:5", "spec/x_spec.rb:9"])
    end

    it "does not consult the lexical fallback when coverage answers" do
      filter.call(mutation(file_path: source_rel, line: 3), ["spec/calc_spec.rb"])
      expect(lexical).not_to have_received(:call) if lexical.respond_to?(:call)
    end
  end

  describe "a true coverage gap (file built, line never executed)" do
    it "returns nil so the mutation is marked :unresolved with zero test runs" do
      result = filter.call(mutation(file_path: source_rel, line: 5), ["spec/calc_spec.rb"])
      expect(result).to be_nil
    end
  end

  describe "a line executed at load but attributed to no example (e.g. a def line)" do
    it "delegates to the lexical filter rather than mis-skipping as :unresolved" do
      mut = mutation(file_path: source_rel, line: 2)
      allow(lexical).to receive(:call).with(mut, ["spec/calc_spec.rb"]).and_return(["spec/calc_spec.rb:5"])

      result = filter.call(mut, ["spec/calc_spec.rb"])

      expect(result).to eq(["spec/calc_spec.rb:5"])
      expect(lexical).to have_received(:call).with(mut, ["spec/calc_spec.rb"])
    end
  end

  describe "a file that was never built (digest miss / partial build)" do
    it "delegates to the lexical filter, passing the original spec_paths" do
      mut = mutation(file_path: "lib/other.rb", line: 2)
      allow(lexical).to receive(:call).with(mut, ["spec/other_spec.rb"]).and_return(["spec/other_spec.rb:4"])

      result = filter.call(mut, ["spec/other_spec.rb"])

      expect(result).to eq(["spec/other_spec.rb:4"])
      expect(lexical).to have_received(:call).with(mut, ["spec/other_spec.rb"])
    end
  end
end
