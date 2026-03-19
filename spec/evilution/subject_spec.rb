# frozen_string_literal: true

RSpec.describe Evilution::Subject do
  let(:node) { instance_double(Prism::DefNode) }

  subject(:subj) do
    described_class.new(
      name: "User#adult?",
      file_path: "lib/user.rb",
      line_number: 9,
      source: "def adult?\n  @age >= 18\nend",
      node: node
    )
  end

  it "exposes name" do
    expect(subj.name).to eq("User#adult?")
  end

  it "exposes file_path" do
    expect(subj.file_path).to eq("lib/user.rb")
  end

  it "exposes line_number" do
    expect(subj.line_number).to eq(9)
  end

  it "exposes source" do
    expect(subj.source).to include("@age >= 18")
  end

  it "exposes node" do
    expect(subj.node).to eq(node)
  end

  describe "#to_s" do
    it "returns name with file and line" do
      expect(subj.to_s).to eq("User#adult? (lib/user.rb:9)")
    end
  end

  describe "#release_node!" do
    it "sets node to nil" do
      subj.release_node!

      expect(subj.node).to be_nil
    end

    it "preserves other attributes" do
      subj.release_node!

      expect(subj.name).to eq("User#adult?")
      expect(subj.file_path).to eq("lib/user.rb")
      expect(subj.line_number).to eq(9)
      expect(subj.source).to include("@age >= 18")
    end
  end
end
