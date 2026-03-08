# frozen_string_literal: true

require "tempfile"

RSpec.describe Evilution::Config do
  describe "defaults" do
    subject(:config) { described_class.new(skip_config_file: true) }

    it "sets target_files to empty array" do
      expect(config.target_files).to eq([])
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

    it "sets line_ranges to empty hash" do
      expect(config.line_ranges).to eq({})
    end
  end

  describe "custom options" do
    it "accepts target_files as array" do
      config = described_class.new(target_files: ["lib/foo.rb", "lib/bar.rb"], skip_config_file: true)

      expect(config.target_files).to eq(["lib/foo.rb", "lib/bar.rb"])
    end

    it "wraps single target_file in array" do
      config = described_class.new(target_files: "lib/foo.rb", skip_config_file: true)

      expect(config.target_files).to eq(["lib/foo.rb"])
    end

    it "warns when jobs option is provided" do
      expect { described_class.new(jobs: 4, skip_config_file: true) }.to output(/no longer supported/).to_stderr
    end

    it "accepts custom timeout" do
      config = described_class.new(timeout: 30, skip_config_file: true)

      expect(config.timeout).to eq(30)
    end

    it "accepts format as string" do
      config = described_class.new(format: "json", skip_config_file: true)

      expect(config.format).to eq(:json)
    end

    it "accepts diff_base" do
      config = described_class.new(diff_base: "HEAD~1", skip_config_file: true)

      expect(config.diff_base).to eq("HEAD~1")
    end

    it "accepts min_score" do
      config = described_class.new(min_score: 0.9, skip_config_file: true)

      expect(config.min_score).to eq(0.9)
    end
  end

  describe "config file loading" do
    around do |example|
      Dir.mktmpdir do |dir|
        Dir.chdir(dir) { example.run }
      end
    end

    it "loads settings from .evilution.yml" do
      File.write(".evilution.yml", "timeout: 30\nformat: json\n")

      config = described_class.new

      expect(config.timeout).to eq(30)
      expect(config.format).to eq(:json)
    end

    it "loads settings from config/evilution.yml" do
      Dir.mkdir("config")
      File.write("config/evilution.yml", "timeout: 20\n")

      config = described_class.new

      expect(config.timeout).to eq(20)
    end

    it "prefers .evilution.yml over config/evilution.yml" do
      File.write(".evilution.yml", "timeout: 30\n")
      Dir.mkdir("config")
      File.write("config/evilution.yml", "timeout: 20\n")

      config = described_class.new

      expect(config.timeout).to eq(30)
    end

    it "CLI options override file settings" do
      File.write(".evilution.yml", "timeout: 30\n")

      config = described_class.new(timeout: 5)

      expect(config.timeout).to eq(5)
    end

    it "handles empty config file gracefully" do
      File.write(".evilution.yml", "")

      config = described_class.new

      expect(config.timeout).to eq(10) # default
    end
  end

  describe ".default_template" do
    it "returns a YAML string with commented-out options" do
      template = described_class.default_template

      expect(template).to include("# timeout:")
      expect(template).to include("# format:")
    end
  end

  describe "#json?" do
    it "returns true when format is json" do
      config = described_class.new(format: :json, skip_config_file: true)

      expect(config.json?).to be true
    end

    it "returns false when format is text" do
      config = described_class.new(format: :text, skip_config_file: true)

      expect(config.json?).to be false
    end
  end

  describe "#text?" do
    it "returns true when format is text" do
      config = described_class.new(format: :text, skip_config_file: true)

      expect(config.text?).to be true
    end

    it "returns false when format is json" do
      config = described_class.new(format: :json, skip_config_file: true)

      expect(config.text?).to be false
    end
  end

  describe "#line_ranges?" do
    it "returns true when line_ranges is non-empty" do
      config = described_class.new(line_ranges: { "lib/foo.rb" => 10..20 }, skip_config_file: true)

      expect(config.line_ranges?).to be true
    end

    it "returns false when line_ranges is empty" do
      config = described_class.new(skip_config_file: true)

      expect(config.line_ranges?).to be false
    end
  end

  describe "#diff?" do
    it "returns true when diff_base is set" do
      config = described_class.new(diff_base: "HEAD~1", skip_config_file: true)

      expect(config.diff?).to be true
    end

    it "returns false when diff_base is nil" do
      config = described_class.new(skip_config_file: true)

      expect(config.diff?).to be false
    end
  end

  describe "immutability" do
    it "is frozen after initialization" do
      config = described_class.new(skip_config_file: true)

      expect(config).to be_frozen
    end
  end
end
