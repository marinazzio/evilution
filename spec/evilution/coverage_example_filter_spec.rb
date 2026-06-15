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

    it "accepts an already-absolute mutation path that matches the map key" do
      result = filter.call(mutation(file_path: source_abs, line: 3), [])
      expect(result).to eq(["spec/calc_spec.rb:5", "spec/x_spec.rb:9"])
    end

    it "does not consult the lexical fallback when coverage answers" do
      allow(lexical).to receive(:call)
      filter.call(mutation(file_path: source_rel, line: 3), ["spec/calc_spec.rb"])
      expect(lexical).not_to have_received(:call)
    end
  end

  describe "a line the map attributes to no example (built file, but no covering example)" do
    # Accuracy-first: never assert a gap on real repos -- a line can be exercised
    # indirectly (before(:all)/load/another spec) that the per-example diff missed.
    # Defer to lexical instead of mis-skipping as :unresolved.
    it "delegates to lexical for a line with no recorded examples (line 5)" do
      mut = mutation(file_path: source_rel, line: 5)
      allow(lexical).to receive(:call).with(mut, ["spec/calc_spec.rb"]).and_return(["spec/calc_spec.rb:5"])

      expect(filter.call(mut, ["spec/calc_spec.rb"])).to eq(["spec/calc_spec.rb:5"])
      expect(lexical).to have_received(:call).with(mut, ["spec/calc_spec.rb"])
    end

    it "delegates to lexical for a load-covered line with no recorded examples (line 2)" do
      mut = mutation(file_path: source_rel, line: 2)
      allow(lexical).to receive(:call).with(mut, ["spec/calc_spec.rb"]).and_return(["spec/calc_spec.rb:9"])

      expect(filter.call(mut, ["spec/calc_spec.rb"])).to eq(["spec/calc_spec.rb:9"])
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
