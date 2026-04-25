# frozen_string_literal: true

require "spec_helper"
require "json"
require "evilution/mcp/info_tool/actions/subjects"

RSpec.describe Evilution::MCP::InfoTool::Actions::Subjects do
  def parse_body(response)
    JSON.parse(response.content.first[:text])
  end

  let(:config) { instance_double(Evilution::Config, skip_heredoc_literals?: false, ignore_patterns: []) }
  let(:subject_stub) do
    instance_double(
      "Evilution::Subject",
      name: "Foo#bar", file_path: "lib/foo.rb", line_number: 10, release_node!: nil
    )
  end
  let(:runner) { instance_double(Evilution::Runner, parse_and_filter_subjects: [subject_stub]) }
  let(:registry) { instance_double(Evilution::Mutator::Registry, mutations_for: Array.new(3)) }

  before do
    allow(Evilution::MCP::InfoTool::ConfigFactory).to receive(:subjects).and_return(config)
    allow(Evilution::Runner).to receive(:new).with(config: config).and_return(runner)
    allow(Evilution::Mutator::Registry).to receive(:default).and_return(registry)
  end

  describe ".call" do
    it "returns a config_error response when files is nil" do
      response = described_class.call(files: nil, line_ranges: nil, target: nil, integration: nil, skip_config: nil)
      body = parse_body(response)
      expect(response.error?).to be true
      expect(body).to eq("error" => { "type" => "config_error", "message" => "files is required" })
    end

    it "returns a config_error response when files is empty" do
      response = described_class.call(files: [], line_ranges: nil, target: nil, integration: nil, skip_config: nil)
      expect(parse_body(response)["error"]["message"]).to eq("files is required")
    end

    it "returns subjects with mutation counts" do
      response = described_class.call(
        files: ["lib/foo.rb"], line_ranges: nil, target: nil, integration: nil, skip_config: nil
      )
      body = parse_body(response)
      expect(body["total_subjects"]).to eq(1)
      expect(body["total_mutations"]).to eq(3)
      expect(body["subjects"]).to eq(
        [{ "name" => "Foo#bar", "file" => "lib/foo.rb", "line" => 10, "mutations" => 3 }]
      )
    end

    it "calls release_node! on each subject after counting" do
      expect(subject_stub).to receive(:release_node!)
      described_class.call(
        files: ["lib/foo.rb"], line_ranges: nil, target: nil, integration: nil, skip_config: nil
      )
    end

    it "builds AST Pattern::Filter when ignore_patterns is non-empty" do
      allow(config).to receive(:ignore_patterns).and_return(["call{name=info}"])
      expect(Evilution::AST::Pattern::Filter).to receive(:new).with(["call{name=info}"]).and_call_original
      described_class.call(
        files: ["lib/foo.rb"], line_ranges: nil, target: nil, integration: nil, skip_config: nil
      )
    end

    it "does not build filter when ignore_patterns is empty" do
      expect(Evilution::AST::Pattern::Filter).not_to receive(:new)
      described_class.call(
        files: ["lib/foo.rb"], line_ranges: nil, target: nil, integration: nil, skip_config: nil
      )
    end

    it "ignores unknown kwargs via **" do
      expect do
        described_class.call(
          files: ["lib/foo.rb"], line_ranges: nil, target: nil, integration: nil,
          skip_config: nil, spec: ["unused.rb"]
        )
      end.not_to raise_error
    end
  end
end
