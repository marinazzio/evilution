# frozen_string_literal: true

require "evilution/mutator/restore_source_cache"
require "evilution/integration/loading/neutralization"

RSpec.describe Evilution::Mutator::RestoreSourceCache do
  let(:neutralizer) do
    Class.new do
      def neutralization(source, file_path:)
        Evilution::Integration::Loading::Neutralization.new(source: "#{file_path}: #{source}", edits: [])
      end
    end.new
  end

  around do |example|
    described_class.clear!
    example.run
    described_class.clear!
  end

  describe ".source_for" do
    it "returns the neutralized source, frozen" do
      source = described_class.source_for("a.rb", "x = 1\n", neutralizer)

      expect(source).to eq("a.rb: x = 1\n")
      expect(source).to be_frozen
    end

    it "neutralizes an unchanged source once" do
      first = described_class.source_for("a.rb", "x = 1\n", neutralizer)

      expect(described_class.source_for("a.rb", +"x = 1\n", neutralizer)).to equal(first)
    end

    it "neutralizes again when the source of a path changes" do
      described_class.source_for("a.rb", "x = 1\n", neutralizer)

      expect(described_class.source_for("a.rb", "y = 2\n", neutralizer)).to eq("a.rb: y = 2\n")
    end

    it "keeps one source per path" do
      first = described_class.source_for("a.rb", "x = 1\n", neutralizer)
      described_class.source_for("b.rb", "x = 1\n", neutralizer)

      expect(described_class.source_for("a.rb", "x = 1\n", neutralizer)).to equal(first)
    end
  end

  describe ".neutralization_for" do
    it "returns the file's neutralization, the restore source being its source" do
      neutralization = described_class.neutralization_for("a.rb", "x = 1\n", neutralizer)

      expect(neutralization).to be_a(Evilution::Integration::Loading::Neutralization)
      expect(described_class.source_for("a.rb", "x = 1\n", neutralizer)).to equal(neutralization.source)
    end

    it "does not hash the source again when handed the same one" do
      source = +"x = 1\n"
      first = described_class.neutralization_for("a.rb", source, neutralizer)
      allow(source).to receive(:hash).and_call_original

      expect(described_class.neutralization_for("a.rb", source, neutralizer)).to equal(first)
      expect(source).not_to have_received(:hash)
    end
  end

  describe ".clear!" do
    it "makes the next lookup neutralize anew" do
      first = described_class.source_for("a.rb", "x = 1\n", neutralizer)
      described_class.clear!

      expect(described_class.source_for("a.rb", "x = 1\n", neutralizer)).not_to equal(first)
    end
  end
end
