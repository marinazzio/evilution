# frozen_string_literal: true

require "evilution/integration/loading/neutralization"

RSpec.describe Evilution::Integration::Loading::Neutralization do
  let(:original) { "class A\n  foo 1\n  def x\n    1\n  end\n  bar\nend\n" }
  let(:def_span) { 18..35 }
  let(:edits) { [[10, 15, "()"], [38, 41, "()"]] }
  let(:neutralization) { described_class.new(source: "class A\n  ()\n  def x\n    1\n  end\n  ()\nend\n", edits: edits) }

  def mutate(source, offset, length, replacement)
    source.b.tap { |bytes| bytes[offset, length] = replacement.b }.force_encoding(source.encoding)
  end

  describe "#carry" do
    it "splices the mutation into the neutralized source, past the edits before it" do
      offset = original.index("1\n  end")
      mutated = mutate(original, offset, 1, "22")

      carried = neutralization.carry(def_span, offset: offset, length: 1, replacement: "22", mutated: mutated)

      expect(carried).to eq("class A\n  ()\n  def x\n    22\n  end\n  ()\nend\n")
    end

    it "is nil when an edit falls in the span" do
      expect(neutralization.carry(5..20, offset: 18, length: 1, replacement: "y", mutated: "")).to be_nil
    end

    it "is nil when an edit touches the span" do
      expect(neutralization.carry(15..35, offset: 20, length: 1, replacement: "y", mutated: "")).to be_nil
      expect(neutralization.carry(18..38, offset: 20, length: 1, replacement: "y", mutated: "")).to be_nil
    end

    it "is the mutated source itself when nothing was neutralized" do
      mutated = +"class A; end\n"
      none = described_class.new(source: original, edits: [])

      expect(none.carry(def_span, offset: 0, length: 1, replacement: "y", mutated: mutated)).to equal(mutated)
    end

    it "is nil when the original could not be neutralized" do
      unknown = described_class.new(source: original, edits: nil)

      expect(unknown.carry(def_span, offset: 20, length: 1, replacement: "y", mutated: "")).to be_nil
    end
  end

  it "exposes the neutralized source and its edits" do
    expect(neutralization).to have_attributes(source: "class A\n  ()\n  def x\n    1\n  end\n  ()\nend\n",
                                              edits: edits)
  end

  it "is frozen" do
    expect(neutralization).to be_frozen
  end
end
