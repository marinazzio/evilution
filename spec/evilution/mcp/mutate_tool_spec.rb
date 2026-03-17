# frozen_string_literal: true

require "json"
require "evilution/mcp/mutate_tool"

RSpec.describe Evilution::MCP::MutateTool do
  let(:mutation) do
    instance_double(
      Evilution::Mutation,
      operator_name: "arithmetic_replacement",
      file_path: "lib/foo.rb",
      line: 10,
      diff: "- a + b\n+ a - b"
    )
  end

  let(:killed_result) do
    instance_double(
      Evilution::Result::MutationResult,
      mutation: mutation,
      status: :killed,
      duration: 0.123,
      killed?: true,
      survived?: false,
      timeout?: false,
      error?: false,
      test_command: "rspec spec/foo_spec.rb"
    )
  end

  let(:summary) do
    instance_double(
      Evilution::Result::Summary,
      results: [killed_result],
      total: 1,
      killed: 1,
      survived: 0,
      timed_out: 0,
      errors: 0,
      neutral: 0,
      score: 1.0,
      duration: 0.5,
      truncated?: false,
      survived_results: [],
      killed_results: [killed_result],
      neutral_results: []
    )
  end

  let(:runner) { instance_double(Evilution::Runner, call: summary) }

  before do
    allow(Evilution::Runner).to receive(:new).and_return(runner)
  end

  describe ".call" do
    it "returns a tool response with JSON results" do
      response = described_class.call(files: ["lib/foo.rb"], server_context: nil)

      expect(response).to be_a(MCP::Tool::Response)
      expect(response.error?).to be false

      parsed = JSON.parse(response.content.first[:text])
      expect(parsed["summary"]["total"]).to eq(1)
      expect(parsed["summary"]["killed"]).to eq(1)
    end

    it "passes files with line ranges to config" do
      described_class.call(files: ["lib/foo.rb:15-30"], server_context: nil)

      expect(Evilution::Runner).to have_received(:new).with(
        config: have_attributes(
          target_files: ["lib/foo.rb"],
          line_ranges: { "lib/foo.rb" => 15..30 }
        )
      )
    end

    it "passes options to config" do
      described_class.call(
        files: ["lib/foo.rb"],
        timeout: 60,
        jobs: 4,
        fail_fast: 2,
        server_context: nil
      )

      expect(Evilution::Runner).to have_received(:new).with(
        config: have_attributes(
          timeout: 60,
          jobs: 4,
          fail_fast: 2
        )
      )
    end

    it "passes target option" do
      described_class.call(files: ["lib/foo.rb"], target: "Foo#bar", server_context: nil)

      expect(Evilution::Runner).to have_received(:new).with(
        config: have_attributes(target: "Foo#bar")
      )
    end

    it "passes spec files option" do
      described_class.call(files: ["lib/foo.rb"], spec: ["spec/foo_spec.rb"], server_context: nil)

      expect(Evilution::Runner).to have_received(:new).with(
        config: have_attributes(spec_files: ["spec/foo_spec.rb"])
      )
    end

    it "returns error response for Evilution errors" do
      allow(runner).to receive(:call).and_raise(Evilution::Error, "no files found")

      response = described_class.call(files: [], server_context: nil)

      expect(response.error?).to be true
      parsed = JSON.parse(response.content.first[:text])
      expect(parsed["error"]["type"]).to eq("runtime_error")
      expect(parsed["error"]["message"]).to eq("no files found")
    end

    it "defaults to empty files when not provided" do
      described_class.call(server_context: nil)

      expect(Evilution::Runner).to have_received(:new).with(
        config: have_attributes(target_files: [])
      )
    end

    it "sets quiet mode to avoid stdout pollution" do
      described_class.call(files: ["lib/foo.rb"], server_context: nil)

      expect(Evilution::Runner).to have_received(:new).with(
        config: have_attributes(quiet: true)
      )
    end

    it "returns parse error for invalid line range" do
      response = described_class.call(files: ["lib/foo.rb:abc"], server_context: nil)

      expect(response.error?).to be true
      parsed = JSON.parse(response.content.first[:text])
      expect(parsed["error"]["type"]).to eq("parse_error")
      expect(parsed["error"]["message"]).to include("invalid line range")
    end
  end
end
