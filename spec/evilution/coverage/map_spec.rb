# frozen_string_literal: true

require "spec_helper"
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

  subject(:map) { described_class.new(index: index, built_files: built_files) }

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

  it "is frozen" do
    expect(map).to be_frozen
  end

  it "round-trips through to_h / from_h" do
    restored = described_class.from_h(map.to_h)
    expect(restored.examples_for("lib/calc.rb", 3)).to eq(map.examples_for("lib/calc.rb", 3))
    expect(restored.built?("lib/calc.rb")).to be(true)
  end
end
