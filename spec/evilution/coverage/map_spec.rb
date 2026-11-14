# frozen_string_literal: true

require "spec_helper"
require "json"
require "evilution/coverage/map"

RSpec.describe Evilution::Coverage::Map do
  let(:index) do
    {
      "lib/calc.rb" => {
        3 => ["spec/calc_spec.rb:5", "spec/calc_spec.rb:9"],
        4 => ["spec/calc_spec.rb:9"]
      }
    }
  end
  let(:built_files) { ["lib/calc.rb"] }
  # Line 2 was executed (e.g. at class load) but is attributed to no example;
  # line 3 was executed inside examples; line 99 never ran.
  let(:executed_lines) { { "lib/calc.rb" => [2, 3] } }

  subject(:map) do
    described_class.new(index: index, built_files: built_files, executed_lines: executed_lines)
  end

  it "returns sorted, de-duplicated example locations for a covered line" do
    expect(map.examples_for("lib/calc.rb", 3)).to eq(["spec/calc_spec.rb:5", "spec/calc_spec.rb:9"])
  end

  it "returns an empty array for a line with no coverage" do
    expect(map.examples_for("lib/calc.rb", 99)).to eq([])
  end

  it "returns an empty array for an unknown file" do
    expect(map.examples_for("lib/other.rb", 3)).to eq([])
  end

  it "reports whether a file was fully built" do
    expect(map.built?("lib/calc.rb")).to be(true)
    expect(map.built?("lib/other.rb")).to be(false)
  end

  it "reports whether a line was executed at all (covered, even if by no single example)" do
    expect(map.executed?("lib/calc.rb", 2)).to be(true)  # load-covered, no example
    expect(map.executed?("lib/calc.rb", 3)).to be(true)  # example-covered
    expect(map.executed?("lib/calc.rb", 99)).to be(false) # never ran -> true gap
    expect(map.executed?("lib/other.rb", 2)).to be(false)
  end

  it "is frozen" do
    expect(map).to be_frozen
  end

  it "freezes its unexecuted lines and spec files" do
    frozen = described_class.new(index: {}, built_files: [], missed_lines: { "lib/calc.rb" => [5] }, spec_files: ["/s"])

    expect(frozen.to_h.values_at("missed_lines", "spec_files")).to all(be_frozen)
    expect(frozen.to_h["missed_lines"]["lib/calc.rb"]).to be_frozen
  end

  # A cache written before unexecuted lines were recorded has neither key.
  it "reads a hash without unexecuted lines or spec files as having none" do
    restored = described_class.from_h("index" => {}, "built_files" => ["lib/calc.rb"])

    expect(restored.uncovered?("lib/calc.rb", [5])).to be(false)
    expect(restored.built_from?(["/s"])).to be(false)
  end

  it "round-trips through to_h / from_h" do
    restored = described_class.from_h(map.to_h)
    expect(restored.examples_for("lib/calc.rb", 3)).to eq(map.examples_for("lib/calc.rb", 3))
    expect(restored.built?("lib/calc.rb")).to be(true)
    expect(restored.executed?("lib/calc.rb", 2)).to be(true)
    expect(restored.executed?("lib/calc.rb", 99)).to be(false)
  end

  describe "#uncovered?" do
    # Line 2 ran at load, line 3 inside examples; lines 5 and 6 are executable
    # but never ran; line 7 is not executable at all (an `end`).
    subject(:map) do
      described_class.new(
        index: index, built_files: built_files,
        executed_lines: { "lib/calc.rb" => [2, 3] },
        missed_lines: { "lib/calc.rb" => [5, 6] }
      )
    end

    it "is true when a line the mutation sits on never ran" do
      expect(map.uncovered?("lib/calc.rb", [5])).to be(true)
    end

    it "is true when every line either never ran or is not executable" do
      expect(map.uncovered?("lib/calc.rb", [5, 6, 7])).to be(true)
    end

    it "is false when any of the lines ran, at load or in an example" do
      expect(map.uncovered?("lib/calc.rb", [2, 5])).to be(false)
      expect(map.uncovered?("lib/calc.rb", [3])).to be(false)
    end

    it "is false when none of the lines is executable" do
      expect(map.uncovered?("lib/calc.rb", [7])).to be(false)
    end

    it "is false for a file the map holds no unexecuted lines for" do
      expect(map.uncovered?("lib/other.rb", [5])).to be(false)
    end
  end

  describe "#built_from?" do
    subject(:map) do
      described_class.new(index: index, built_files: built_files, spec_files: ["/p/spec/a_spec.rb", "/p/spec/b_spec.rb"])
    end

    it "is true when the build ran every one of the spec files" do
      expect(map.built_from?(["/p/spec/a_spec.rb"])).to be(true)
      expect(map.built_from?(["/p/spec/b_spec.rb", "/p/spec/a_spec.rb"])).to be(true)
    end

    it "is false when any spec file was not part of the build" do
      expect(map.built_from?(["/p/spec/a_spec.rb", "/p/spec/c_spec.rb"])).to be(false)
      expect(map.built_from?(["/p/spec"])).to be(false)
    end

    it "is false for no spec files at all" do
      expect(map.built_from?([])).to be(false)
    end
  end

  it "round-trips its unexecuted lines and spec files through to_h / from_h" do
    original = described_class.new(
      index: index, built_files: built_files, executed_lines: executed_lines,
      missed_lines: { "lib/calc.rb" => [5] }, spec_files: ["/p/spec/a_spec.rb"]
    )
    restored = described_class.from_h(JSON.parse(JSON.generate(original.to_h)))

    expect(restored.uncovered?("lib/calc.rb", [5])).to be(true)
    expect(restored.built_from?(["/p/spec/a_spec.rb"])).to be(true)
  end
end
