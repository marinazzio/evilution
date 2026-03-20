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
      neutral?: false,
      test_command: "rspec spec/foo_spec.rb",
      child_rss_kb: nil,
      memory_delta_kb: nil
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
      equivalent: 0,
      score: 1.0,
      duration: 0.5,
      truncated?: false,
      survived_results: [],
      killed_results: [killed_result],
      neutral_results: [],
      equivalent_results: [],
      peak_memory_mb: nil
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

    context "response trimming" do
      it "strips diffs from killed mutations" do
        response = described_class.call(files: ["lib/foo.rb"], verbosity: "full", server_context: nil)

        parsed = JSON.parse(response.content.first[:text])
        killed_entry = parsed["killed"].first
        expect(killed_entry).not_to have_key("diff")
        expect(killed_entry["operator"]).to eq("arithmetic_replacement")
        expect(killed_entry["file"]).to eq("lib/foo.rb")
        expect(killed_entry["line"]).to eq(10)
      end

      it "preserves timed_out entries with full details" do
        timed_out_result = instance_double(
          Evilution::Result::MutationResult,
          mutation: mutation,
          status: :timeout,
          duration: 30.0,
          killed?: false,
          survived?: false,
          timeout?: true,
          error?: false,
          neutral?: false,
          test_command: "rspec spec/foo_spec.rb",
          child_rss_kb: nil,
          memory_delta_kb: nil
        )
        timed_out_summary = instance_double(
          Evilution::Result::Summary,
          results: [timed_out_result],
          total: 1,
          killed: 0,
          survived: 0,
          timed_out: 1,
          errors: 0,
          neutral: 0,
          score: 0.0,
          duration: 30.0,
          truncated?: false,
          survived_results: [],
          killed_results: [],
          neutral_results: [],
          equivalent: 0,
          equivalent_results: [],
          peak_memory_mb: nil
        )
        allow(runner).to receive(:call).and_return(timed_out_summary)

        response = described_class.call(files: ["lib/foo.rb"], server_context: nil)

        parsed = JSON.parse(response.content.first[:text])
        expect(parsed["timed_out"].first["diff"]).to eq("- a + b\n+ a - b")
      end

      it "preserves errors entries with full details" do
        error_result = instance_double(
          Evilution::Result::MutationResult,
          mutation: mutation,
          status: :error,
          duration: 0.05,
          killed?: false,
          survived?: false,
          timeout?: false,
          error?: true,
          neutral?: false,
          test_command: "rspec spec/foo_spec.rb",
          child_rss_kb: nil,
          memory_delta_kb: nil
        )
        error_summary = instance_double(
          Evilution::Result::Summary,
          results: [error_result],
          total: 1,
          killed: 0,
          survived: 0,
          timed_out: 0,
          errors: 1,
          neutral: 0,
          score: 0.0,
          duration: 0.05,
          truncated?: false,
          survived_results: [],
          killed_results: [],
          neutral_results: [],
          equivalent: 0,
          equivalent_results: [],
          peak_memory_mb: nil
        )
        allow(runner).to receive(:call).and_return(error_summary)

        response = described_class.call(files: ["lib/foo.rb"], server_context: nil)

        parsed = JSON.parse(response.content.first[:text])
        expect(parsed["errors"].first["diff"]).to eq("- a + b\n+ a - b")
      end

      it "strips diffs from neutral mutations" do
        neutral_result = instance_double(
          Evilution::Result::MutationResult,
          mutation: mutation,
          status: :neutral,
          duration: 0.1,
          killed?: false,
          survived?: false,
          timeout?: false,
          error?: false,
          neutral?: true,
          test_command: "rspec spec/foo_spec.rb",
          child_rss_kb: nil,
          memory_delta_kb: nil
        )
        neutral_summary = instance_double(
          Evilution::Result::Summary,
          results: [neutral_result],
          total: 1,
          killed: 0,
          survived: 0,
          timed_out: 0,
          errors: 0,
          neutral: 1,
          score: 0.0,
          duration: 0.1,
          truncated?: false,
          survived_results: [],
          killed_results: [],
          neutral_results: [neutral_result],
          equivalent: 0,
          equivalent_results: [],
          peak_memory_mb: nil
        )
        allow(runner).to receive(:call).and_return(neutral_summary)

        response = described_class.call(files: ["lib/foo.rb"], verbosity: "full", server_context: nil)

        parsed = JSON.parse(response.content.first[:text])
        neutral_entry = parsed["neutral"].first
        expect(neutral_entry).not_to have_key("diff")
        expect(neutral_entry["operator"]).to eq("arithmetic_replacement")
      end

      it "preserves survived mutation details with diffs" do
        survived_mutation = instance_double(
          Evilution::Mutation,
          operator_name: "statement_deletion",
          file_path: "lib/foo.rb",
          line: 5,
          diff: "- x = 1\n+ "
        )
        survived_result = instance_double(
          Evilution::Result::MutationResult,
          mutation: survived_mutation,
          status: :survived,
          duration: 0.1,
          killed?: false,
          survived?: true,
          timeout?: false,
          error?: false,
          neutral?: false,
          test_command: "rspec spec/foo_spec.rb",
          child_rss_kb: nil,
          memory_delta_kb: nil
        )
        survived_summary = instance_double(
          Evilution::Result::Summary,
          results: [survived_result],
          total: 1,
          killed: 0,
          survived: 1,
          timed_out: 0,
          errors: 0,
          neutral: 0,
          score: 0.0,
          duration: 0.5,
          truncated?: false,
          survived_results: [survived_result],
          killed_results: [],
          neutral_results: [],
          equivalent: 0,
          equivalent_results: [],
          peak_memory_mb: nil
        )
        allow(runner).to receive(:call).and_return(survived_summary)

        response = described_class.call(files: ["lib/foo.rb"], server_context: nil)

        parsed = JSON.parse(response.content.first[:text])
        expect(parsed["survived"].length).to eq(1)
        expect(parsed["survived"].first["diff"]).to eq("- x = 1\n+ ")
      end

      it "preserves summary counts" do
        response = described_class.call(files: ["lib/foo.rb"], server_context: nil)

        parsed = JSON.parse(response.content.first[:text])
        expect(parsed["summary"]["total"]).to eq(1)
        expect(parsed["summary"]["killed"]).to eq(1)
        expect(parsed["summary"]["score"]).to eq(1.0)
      end
    end

    context "verbosity control" do
      it "defaults to summary verbosity (omits killed/neutral/equivalent arrays)" do
        response = described_class.call(files: ["lib/foo.rb"], server_context: nil)

        parsed = JSON.parse(response.content.first[:text])
        expect(parsed).not_to have_key("killed")
        expect(parsed).not_to have_key("neutral")
        expect(parsed).not_to have_key("equivalent")
        expect(parsed).to have_key("summary")
        expect(parsed).to have_key("survived")
        expect(parsed).to have_key("timed_out")
        expect(parsed).to have_key("errors")
      end

      it "keeps all entries with diffs stripped in full verbosity" do
        response = described_class.call(files: ["lib/foo.rb"], verbosity: "full", server_context: nil)

        parsed = JSON.parse(response.content.first[:text])
        expect(parsed).to have_key("killed")
        expect(parsed).to have_key("neutral")
        expect(parsed).to have_key("equivalent")
        expect(parsed["killed"].first).not_to have_key("diff")
      end

      it "keeps only summary and survived in minimal verbosity" do
        response = described_class.call(files: ["lib/foo.rb"], verbosity: "minimal", server_context: nil)

        parsed = JSON.parse(response.content.first[:text])
        expect(parsed).to have_key("summary")
        expect(parsed).to have_key("survived")
        expect(parsed).not_to have_key("killed")
        expect(parsed).not_to have_key("neutral")
        expect(parsed).not_to have_key("equivalent")
        expect(parsed).not_to have_key("timed_out")
        expect(parsed).not_to have_key("errors")
      end

      it "accepts summary verbosity explicitly" do
        response = described_class.call(files: ["lib/foo.rb"], verbosity: "summary", server_context: nil)

        parsed = JSON.parse(response.content.first[:text])
        expect(parsed).not_to have_key("killed")
        expect(parsed).to have_key("survived")
        expect(parsed).to have_key("summary")
      end
    end
  end
end
