# frozen_string_literal: true

RSpec.describe Evilution::Config do
  describe "defaults" do
    subject(:config) { described_class.new }

    it "sets target_files to empty array" do
      expect(config.target_files).to eq([])
    end

    it "sets jobs to processor count" do
      expect(config.jobs).to be_a(Integer)
      expect(config.jobs).to be >= 1
    end

    it "sets timeout to 10 seconds" do
      expect(config.timeout).to eq(10)
    end

    it "sets format to :text" do
      expect(config.format).to eq(:text)
    end

    it "sets min_score to 0.0" do
      expect(config.min_score).to eq(0.0)
    end

    it "sets integration to :rspec" do
      expect(config.integration).to eq(:rspec)
    end

    it "enables coverage by default" do
      expect(config.coverage).to be true
    end

    it "disables verbose by default" do
      expect(config.verbose).to be false
    end

    it "disables quiet by default" do
      expect(config.quiet).to be false
    end

    it "sets diff_base to nil" do
      expect(config.diff_base).to be_nil
    end
  end

  describe "custom options" do
    it "accepts target_files as array" do
      config = described_class.new(target_files: ["lib/foo.rb", "lib/bar.rb"])

      expect(config.target_files).to eq(["lib/foo.rb", "lib/bar.rb"])
    end

    it "wraps single target_file in array" do
      config = described_class.new(target_files: "lib/foo.rb")

      expect(config.target_files).to eq(["lib/foo.rb"])
    end

    it "accepts custom jobs count" do
      config = described_class.new(jobs: 2)

      expect(config.jobs).to eq(2)
    end

    it "accepts custom timeout" do
      config = described_class.new(timeout: 30)

      expect(config.timeout).to eq(30)
    end

    it "accepts format as string" do
      config = described_class.new(format: "json")

      expect(config.format).to eq(:json)
    end

    it "accepts diff_base" do
      config = described_class.new(diff_base: "HEAD~1")

      expect(config.diff_base).to eq("HEAD~1")
    end

    it "accepts min_score" do
      config = described_class.new(min_score: 0.9)

      expect(config.min_score).to eq(0.9)
    end
  end

  describe "#json?" do
    it "returns true when format is json" do
      config = described_class.new(format: :json)

      expect(config.json?).to be true
    end

    it "returns false when format is text" do
      config = described_class.new(format: :text)

      expect(config.json?).to be false
    end
  end

  describe "#text?" do
    it "returns true when format is text" do
      config = described_class.new(format: :text)

      expect(config.text?).to be true
    end

    it "returns false when format is json" do
      config = described_class.new(format: :json)

      expect(config.text?).to be false
    end
  end

  describe "#diff?" do
    it "returns true when diff_base is set" do
      config = described_class.new(diff_base: "HEAD~1")

      expect(config.diff?).to be true
    end

    it "returns false when diff_base is nil" do
      config = described_class.new

      expect(config.diff?).to be false
    end
  end

  describe "immutability" do
    it "is frozen after initialization" do
      config = described_class.new

      expect(config).to be_frozen
    end
  end
end
