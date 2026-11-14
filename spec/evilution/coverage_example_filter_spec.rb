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

  describe "#warm" do
    # Coverage answers from its map; the lexical filter is what it falls back
    # on, and its caches are what a forked child would otherwise fill.
    it "warms the lexical filter it falls back on" do
      m = mutation(file_path: source_rel, line: 3)
      allow(lexical).to receive(:warm)

      filter.warm(m, ["spec/calc_spec.rb"])

      expect(lexical).to have_received(:warm).with(m, ["spec/calc_spec.rb"])
    end
  end

  describe "#uncovered?" do
    # Line 5 is executable and never ran; line 2 ran at load; line 7 is not
    # executable. The build ran spec/calc_spec.rb.
    let(:map) do
      Evilution::Coverage::Map.new(
        index: { source_abs => { 3 => ["spec/calc_spec.rb:5"] } },
        built_files: [source_abs],
        executed_lines: { source_abs => [2, 3] },
        missed_lines: { source_abs => [5] },
        spec_files: ["/proj/spec/calc_spec.rb"]
      )
    end

    def located(line:, lines: line..line)
      instance_double(Evilution::Mutation, file_path: source_rel, line: line, changed_lines: lines)
    end

    it "is true for a mutation on a line no example and no load executed" do
      expect(filter.uncovered?(located(line: 5), ["spec/calc_spec.rb"])).to be(true)
    end

    it "is false when a line the mutation changes ran" do
      expect(filter.uncovered?(located(line: 5, lines: 2..5), ["spec/calc_spec.rb"])).to be(false)
    end

    # A method body's mutation is reported at its `def`, which ran while the
    # file loaded; what it changes is the body, which never ran.
    it "goes by the lines the mutation changes, not the line it is reported at" do
      expect(filter.uncovered?(located(line: 2, lines: 5..5), ["spec/calc_spec.rb"])).to be(true)
      expect(filter.uncovered?(located(line: 5, lines: 2..2), ["spec/calc_spec.rb"])).to be(false)
    end

    it "is false for a line that ran only while the file loaded" do
      expect(filter.uncovered?(located(line: 2), ["spec/calc_spec.rb"])).to be(false)
    end

    it "is false when the mutation would run a spec file the map was not built from" do
      expect(filter.uncovered?(located(line: 5), ["spec/calc_spec.rb", "spec/other_spec.rb"])).to be(false)
      expect(filter.uncovered?(located(line: 5), ["spec"])).to be(false)
    end

    it "is false when the mutation has no spec file to run" do
      expect(filter.uncovered?(located(line: 5), [])).to be(false)
      expect(filter.uncovered?(located(line: 5), ["spec/calc_spec.rb"])).to be(true)
      expect(filter.uncovered?(located(line: 5), nil)).to be(false)
    end
  end
end
