# frozen_string_literal: true

require "spec_helper"
require "evilution/mcp/info_tool/config_factory"

RSpec.describe Evilution::MCP::InfoTool::ConfigFactory do
  describe ".subjects" do
    it "returns an Evilution::Config with target_files set" do
      config = described_class.subjects(
        files: ["lib/foo.rb"], line_ranges: nil, target: nil, integration: nil, skip_config: nil
      )
      expect(config).to be_a(Evilution::Config)
      expect(config.target_files).to eq(["lib/foo.rb"])
      expect(config.line_ranges).to eq({})
    end

    it "preserves line_ranges when provided" do
      ranges = { "lib/foo.rb" => (1..3) }
      config = described_class.subjects(
        files: ["lib/foo.rb"], line_ranges: ranges, target: nil, integration: nil, skip_config: nil
      )
      expect(config.line_ranges).to eq(ranges)
    end

    it "sets target when provided" do
      config = described_class.subjects(
        files: ["lib/foo.rb"], line_ranges: nil, target: "Foo#bar", integration: nil, skip_config: nil
      )
      expect(config.target).to eq("Foo#bar")
    end

    it "sets integration when provided" do
      config = described_class.subjects(
        files: ["lib/foo.rb"], line_ranges: nil, target: nil, integration: "minitest", skip_config: nil
      )
      expect(config.integration).to eq(:minitest)
    end

    it "passes skip_config_file: true when skip_config is truthy" do
      expect(Evilution::Config).to receive(:new).with(hash_including(skip_config_file: true))
      described_class.subjects(
        files: ["lib/foo.rb"], line_ranges: nil, target: nil, integration: nil, skip_config: true
      )
    end

    it "omits skip_config_file when skip_config is falsy" do
      expect(Evilution::Config).to receive(:new) do |opts|
        expect(opts).not_to have_key(:skip_config_file)
      end
      described_class.subjects(
        files: ["lib/foo.rb"], line_ranges: nil, target: nil, integration: nil, skip_config: nil
      )
    end
  end

  describe ".tests" do
    it "returns an Evilution::Config with target_files set" do
      config = described_class.tests(
        files: ["lib/foo.rb"], spec: nil, integration: nil, skip_config: nil
      )
      expect(config.target_files).to eq(["lib/foo.rb"])
    end

    it "sets spec_files when spec provided" do
      config = described_class.tests(
        files: ["lib/foo.rb"], spec: ["spec/foo_spec.rb"], integration: nil, skip_config: nil
      )
      expect(config.spec_files).to eq(["spec/foo_spec.rb"])
    end

    it "sets integration when provided" do
      config = described_class.tests(
        files: ["lib/foo.rb"], spec: nil, integration: "minitest", skip_config: nil
      )
      expect(config.integration).to eq(:minitest)
    end

    it "passes skip_config_file: true when skip_config is truthy" do
      expect(Evilution::Config).to receive(:new).with(hash_including(skip_config_file: true))
      described_class.tests(files: ["lib/foo.rb"], spec: nil, integration: nil, skip_config: true)
    end
  end
end
