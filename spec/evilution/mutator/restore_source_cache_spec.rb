# frozen_string_literal: true

require "evilution/mutator/restore_source_cache"

RSpec.describe Evilution::Mutator::RestoreSourceCache do
  let(:neutralizer) { ->(source, file_path:) { "#{file_path}: #{source}" } }

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

  describe ".clear!" do
    it "makes the next lookup neutralize anew" do
      first = described_class.source_for("a.rb", "x = 1\n", neutralizer)
      described_class.clear!

      expect(described_class.source_for("a.rb", "x = 1\n", neutralizer)).not_to equal(first)
    end
  end
end
