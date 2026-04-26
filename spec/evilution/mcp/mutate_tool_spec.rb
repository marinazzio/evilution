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
      diff: "- a + b\n+ a - b",
      unified_diff: nil
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
      parent_rss_kb: nil,
      error_message: nil,
      error_class: nil,
      error_backtrace: nil,
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
      unparseable: 0,
      unparseable_results: [],
      score: 1.0,
      duration: 0.5,
      killtime: 0.123,
      efficiency: 0.246,
      mutations_per_second: 2.0,
      truncated?: false,
      survived_results: [],
      killed_results: [killed_result],
      neutral_results: [],
      equivalent_results: [],
      peak_memory_mb: nil,
      skipped: 0,
      disabled_mutations: [],
      coverage_gaps: [],
      unresolved: 0,
      unresolved_results: []
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
        on_result: anything,
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
        on_result: anything,
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
        on_result: anything,
        config: have_attributes(target: "Foo#bar")
      )
    end

    it "passes spec files option" do
      described_class.call(files: ["lib/foo.rb"], spec: ["spec/foo_spec.rb"], server_context: nil)

      expect(Evilution::Runner).to have_received(:new).with(
        on_result: anything,
        config: have_attributes(spec_files: ["spec/foo_spec.rb"])
      )
    end

    it "passes suggest_tests option" do
      described_class.call(files: ["lib/foo.rb"], suggest_tests: true, server_context: nil)

      expect(Evilution::Runner).to have_received(:new).with(
        on_result: anything,
        config: have_attributes(suggest_tests: true)
      )
    end

    it "defaults suggest_tests to false" do
      described_class.call(files: ["lib/foo.rb"], server_context: nil)

      expect(Evilution::Runner).to have_received(:new).with(
        on_result: anything,
        config: have_attributes(suggest_tests: false)
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
        on_result: anything,
        config: have_attributes(target_files: [])
      )
    end

    it "sets quiet mode to avoid stdout pollution" do
      described_class.call(files: ["lib/foo.rb"], server_context: nil)

      expect(Evilution::Runner).to have_received(:new).with(
        on_result: anything,
        config: have_attributes(quiet: true)
      )
    end

    it "passes incremental option to config" do
      described_class.call(files: ["lib/foo.rb"], incremental: true, server_context: nil)

      expect(Evilution::Runner).to have_received(:new).with(
        on_result: anything,
        config: have_attributes(incremental: true)
      )
    end

    it "passes integration option to config" do
      described_class.call(files: ["lib/foo.rb"], integration: "minitest", server_context: nil)

      expect(Evilution::Runner).to have_received(:new).with(
        on_result: anything,
        config: have_attributes(integration: :minitest)
      )
    end

    it "passes isolation option to config" do
      described_class.call(files: ["lib/foo.rb"], isolation: "fork", server_context: nil)

      expect(Evilution::Runner).to have_received(:new).with(
        on_result: anything,
        config: have_attributes(isolation: :fork)
      )
    end

    it "passes save_session option to config" do
      described_class.call(files: ["lib/foo.rb"], save_session: true, server_context: nil)

      expect(Evilution::Runner).to have_received(:new).with(
        on_result: anything,
        config: have_attributes(save_session: true)
      )
    end

    it "returns parse error for unknown keyword parameters" do
      response = described_class.call(files: ["lib/foo.rb"], totally_bogus: 1, server_context: nil)

      expect(response.error?).to be true
      parsed = JSON.parse(response.content.first[:text])
      expect(parsed["error"]["type"]).to eq("parse_error")
      expect(parsed["error"]["message"]).to include("totally_bogus")
    end

    it "lets explicit baseline: false disable the baseline check" do
      described_class.call(files: ["lib/foo.rb"], baseline: false, server_context: nil)

      expect(Evilution::Runner).to have_received(:new).with(
        on_result: anything,
        config: have_attributes(baseline: false)
      )
    end

    it "defaults baseline to true when not provided" do
      described_class.call(files: ["lib/foo.rb"], server_context: nil)

      expect(Evilution::Runner).to have_received(:new).with(
        on_result: anything,
        config: have_attributes(baseline: true)
      )
    end

    it "returns parse error for invalid line range" do
      response = described_class.call(files: ["lib/foo.rb:abc"], server_context: nil)

      expect(response.error?).to be true
      parsed = JSON.parse(response.content.first[:text])
      expect(parsed["error"]["type"]).to eq("parse_error")
      expect(parsed["error"]["message"]).to include("invalid line range")
    end

    context "config file handling" do
      around do |example|
        Dir.mktmpdir do |dir|
          Dir.chdir(dir) { example.run }
        end
      end

      it "loads settings from .evilution.yml by default" do
        File.write(".evilution.yml", "timeout: 42\njobs: 3\n")

        described_class.call(files: ["lib/foo.rb"], server_context: nil)

        expect(Evilution::Runner).to have_received(:new).with(
          on_result: anything,
          config: have_attributes(timeout: 42, jobs: 3)
        )
      end

      it "lets explicit params override .evilution.yml settings" do
        File.write(".evilution.yml", "timeout: 42\njobs: 3\n")

        described_class.call(files: ["lib/foo.rb"], timeout: 5, server_context: nil)

        expect(Evilution::Runner).to have_received(:new).with(
          on_result: anything,
          config: have_attributes(timeout: 5, jobs: 3)
        )
      end

      it "skips .evilution.yml when skip_config is true" do
        File.write(".evilution.yml", "timeout: 42\n")

        described_class.call(files: ["lib/foo.rb"], skip_config: true, server_context: nil)

        expect(Evilution::Runner).to have_received(:new).with(
          on_result: anything,
          config: have_attributes(timeout: Evilution::Config::DEFAULTS[:timeout])
        )
      end

      it "lets explicit suggest_tests: false override .evilution.yml setting" do
        File.write(".evilution.yml", "suggest_tests: true\n")

        described_class.call(files: ["lib/foo.rb"], suggest_tests: false, server_context: nil)

        expect(Evilution::Runner).to have_received(:new).with(
          on_result: anything,
          config: have_attributes(suggest_tests: false)
        )
      end

      it "forces preload to false even when .evilution.yml enables it" do
        File.write(".evilution.yml", "preload: true\n")

        described_class.call(files: ["lib/foo.rb"], server_context: nil)

        expect(Evilution::Runner).to have_received(:new).with(
          on_result: anything,
          config: have_attributes(preload: false)
        )
      end
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
          parent_rss_kb: nil,
          error_message: nil,
          error_class: nil,
          error_backtrace: nil,
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
          killtime: 30.0,
          efficiency: 1.0,
          mutations_per_second: 0.033,
          truncated?: false,
          survived_results: [],
          killed_results: [],
          neutral_results: [],
          equivalent: 0,
          equivalent_results: [],
          peak_memory_mb: nil,
          skipped: 0,
          disabled_mutations: [],
          coverage_gaps: [],
          unresolved: 0,
          unresolved_results: [],
          unparseable: 0,
          unparseable_results: []
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
          parent_rss_kb: nil,
          error_message: nil,
          error_class: nil,
          error_backtrace: nil,
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
          killtime: 0.05,
          efficiency: 1.0,
          mutations_per_second: 20.0,
          truncated?: false,
          survived_results: [],
          killed_results: [],
          neutral_results: [],
          equivalent: 0,
          equivalent_results: [],
          peak_memory_mb: nil,
          skipped: 0,
          disabled_mutations: [],
          coverage_gaps: [],
          unresolved: 0,
          unresolved_results: [],
          unparseable: 0,
          unparseable_results: []
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
          parent_rss_kb: nil,
          error_message: nil,
          error_class: nil,
          error_backtrace: nil,
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
          killtime: 0.1,
          efficiency: 1.0,
          mutations_per_second: 10.0,
          truncated?: false,
          survived_results: [],
          killed_results: [],
          neutral_results: [neutral_result],
          equivalent: 0,
          equivalent_results: [],
          peak_memory_mb: nil,
          skipped: 0,
          disabled_mutations: [],
          coverage_gaps: [],
          unresolved: 0,
          unresolved_results: [],
          unparseable: 0,
          unparseable_results: []
        )
        allow(runner).to receive(:call).and_return(neutral_summary)

        response = described_class.call(files: ["lib/foo.rb"], verbosity: "full", server_context: nil)

        parsed = JSON.parse(response.content.first[:text])
        neutral_entry = parsed["neutral"].first
        expect(neutral_entry).not_to have_key("diff")
        expect(neutral_entry["operator"]).to eq("arithmetic_replacement")
      end

      it "preserves survived mutation details with diffs" do
        survived_subject = instance_double(Evilution::Subject, name: "Foo#bar")
        survived_mutation = instance_double(
          Evilution::Mutation,
          operator_name: "statement_deletion",
          file_path: "lib/foo.rb",
          line: 5,
          diff: "- x = 1\n+ ",
          unified_diff: "--- a/lib/foo.rb\n+++ b/lib/foo.rb\n@@ -5,1 +5,0 @@\n-x = 1",
          subject: survived_subject
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
          parent_rss_kb: nil,
          error_message: nil,
          error_class: nil,
          error_backtrace: nil,
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
          killtime: 0.123,
          efficiency: 0.246,
          mutations_per_second: 2.0,
          truncated?: false,
          survived_results: [survived_result],
          killed_results: [],
          neutral_results: [],
          equivalent: 0,
          equivalent_results: [],
          peak_memory_mb: nil,
          skipped: 0,
          disabled_mutations: [],
          coverage_gaps: [],
          unresolved: 0,
          unresolved_results: [],
          unparseable: 0,
          unparseable_results: []
        )
        allow(runner).to receive(:call).and_return(survived_summary)

        response = described_class.call(files: ["lib/foo.rb"], server_context: nil)

        parsed = JSON.parse(response.content.first[:text])
        expect(parsed["survived"].length).to eq(1)
        expect(parsed["survived"].first["diff"]).to eq("- x = 1\n+ ")
      end

      context "survived enrichment" do
        let(:survived_subject) { instance_double(Evilution::Subject, name: "Foo#bar") }
        let(:survived_mutation) do
          instance_double(
            Evilution::Mutation,
            operator_name: "statement_deletion",
            file_path: "lib/foo.rb",
            line: 5,
            diff: "- x = 1\n+ ",
            unified_diff: nil,
            subject: survived_subject
          )
        end
        let(:survived_result) do
          instance_double(
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
            parent_rss_kb: nil,
            error_message: nil,
            error_class: nil,
            error_backtrace: nil,
            memory_delta_kb: nil
          )
        end
        let(:survived_summary) do
          instance_double(
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
            killtime: 0.1,
            efficiency: 0.2,
            mutations_per_second: 2.0,
            truncated?: false,
            survived_results: [survived_result],
            killed_results: [],
            neutral_results: [],
            equivalent: 0,
            equivalent_results: [],
            peak_memory_mb: nil,
            skipped: 0,
            disabled_mutations: [],
            coverage_gaps: [],
            unresolved: 0,
            unresolved_results: [],
            unparseable: 0,
            unparseable_results: []
          )
        end

        before { allow(runner).to receive(:call).and_return(survived_summary) }

        it "adds the subject name to survived entries" do
          response = described_class.call(files: ["lib/foo.rb"], server_context: nil)

          entry = JSON.parse(response.content.first[:text])["survived"].first
          expect(entry["subject"]).to eq("Foo#bar")
        end

        it "resolves and adds spec_file to survived entries when a spec is found" do
          resolver = instance_double(Evilution::SpecResolver, call: "spec/foo_spec.rb")
          allow(Evilution::SpecResolver).to receive(:new).and_return(resolver)

          response = described_class.call(files: ["lib/foo.rb"], server_context: nil)

          entry = JSON.parse(response.content.first[:text])["survived"].first
          expect(resolver).to have_received(:call).with("lib/foo.rb")
          expect(entry["spec_file"]).to eq("spec/foo_spec.rb")
        end

        it "omits spec_file when no spec can be resolved" do
          resolver = instance_double(Evilution::SpecResolver, call: nil)
          allow(Evilution::SpecResolver).to receive(:new).and_return(resolver)

          response = described_class.call(files: ["lib/foo.rb"], server_context: nil)

          entry = JSON.parse(response.content.first[:text])["survived"].first
          expect(entry).not_to have_key("spec_file")
        end

        it "adds an actionable next_step hint to survived entries" do
          response = described_class.call(files: ["lib/foo.rb"], server_context: nil)

          entry = JSON.parse(response.content.first[:text])["survived"].first
          expect(entry["next_step"]).to be_a(String)
          expect(entry["next_step"]).not_to be_empty
        end

        it "enriches survived entries in minimal verbosity too" do
          response = described_class.call(files: ["lib/foo.rb"], verbosity: "minimal", server_context: nil)

          entry = JSON.parse(response.content.first[:text])["survived"].first
          expect(entry["subject"]).to eq("Foo#bar")
          expect(entry["next_step"]).to be_a(String)
        end

        it "uses the minitest spec resolver when integration is minitest" do
          minitest_resolver = instance_double(Evilution::SpecResolver, call: "test/foo_test.rb")
          allow(Evilution::Runner::INTEGRATIONS[:minitest])
            .to receive(:baseline_options).and_return(spec_resolver: minitest_resolver)

          response = described_class.call(files: ["lib/foo.rb"], integration: "minitest", server_context: nil)

          entry = JSON.parse(response.content.first[:text])["survived"].first
          expect(minitest_resolver).to have_received(:call).with("lib/foo.rb")
          expect(entry["spec_file"]).to eq("test/foo_test.rb")
        end

        it "uses the explicit spec override as spec_file instead of auto-resolving" do
          resolver = instance_double(Evilution::SpecResolver, call: nil)
          allow(Evilution::SpecResolver).to receive(:new).and_return(resolver)

          response = described_class.call(
            files: ["lib/foo.rb"],
            spec: ["spec/custom_override_spec.rb"],
            server_context: nil
          )

          entry = JSON.parse(response.content.first[:text])["survived"].first
          expect(resolver).not_to have_received(:call)
          expect(entry["spec_file"]).to eq("spec/custom_override_spec.rb")
        end

        it "caches resolver lookups for survivors from the same file" do
          second_result = instance_double(
            Evilution::Result::MutationResult,
            mutation: survived_mutation,
            status: :survived,
            duration: 0.1,
            killed?: false,
            survived?: true,
            timeout?: false,
            error?: false,
            neutral?: false,
            test_command: nil,
            child_rss_kb: nil,
            parent_rss_kb: nil,
            error_message: nil,
            error_class: nil,
            error_backtrace: nil,
            memory_delta_kb: nil
          )
          allow(survived_summary).to receive(:survived_results).and_return([survived_result, second_result])

          resolver = instance_double(Evilution::SpecResolver, call: "spec/foo_spec.rb")
          allow(Evilution::SpecResolver).to receive(:new).and_return(resolver)

          described_class.call(files: ["lib/foo.rb"], server_context: nil)

          expect(resolver).to have_received(:call).with("lib/foo.rb").once
        end
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

      it "treats empty string verbosity as summary default" do
        response = described_class.call(files: ["lib/foo.rb"], verbosity: "", server_context: nil)

        parsed = JSON.parse(response.content.first[:text])
        expect(parsed).not_to have_key("killed")
        expect(parsed).to have_key("summary")
      end

      it "treats nil verbosity as summary default" do
        response = described_class.call(files: ["lib/foo.rb"], verbosity: nil, server_context: nil)

        parsed = JSON.parse(response.content.first[:text])
        expect(parsed).not_to have_key("killed")
        expect(parsed).to have_key("summary")
      end

      it "returns error for invalid verbosity" do
        response = described_class.call(files: ["lib/foo.rb"], verbosity: "verbose", server_context: nil)

        expect(response.error?).to be true
        parsed = JSON.parse(response.content.first[:text])
        expect(parsed["error"]["type"]).to eq("parse_error")
        expect(parsed["error"]["message"]).to include("invalid verbosity")
      end

      it "strips diffs from equivalent entries in full verbosity" do
        equivalent_result = instance_double(
          Evilution::Result::MutationResult,
          mutation: mutation,
          status: :equivalent,
          duration: 0.0,
          killed?: false,
          survived?: false,
          timeout?: false,
          error?: false,
          neutral?: false,
          test_command: nil,
          child_rss_kb: nil,
          parent_rss_kb: nil,
          error_message: nil,
          error_class: nil,
          error_backtrace: nil,
          memory_delta_kb: nil
        )
        equivalent_summary = instance_double(
          Evilution::Result::Summary,
          results: [equivalent_result],
          total: 1,
          killed: 0,
          survived: 0,
          timed_out: 0,
          errors: 0,
          neutral: 0,
          equivalent: 1,
          score: 0.0,
          duration: 0.0,
          killtime: 0.0,
          efficiency: 0.0,
          mutations_per_second: 0.0,
          truncated?: false,
          survived_results: [],
          killed_results: [],
          neutral_results: [],
          equivalent_results: [equivalent_result],
          peak_memory_mb: nil,
          skipped: 0,
          disabled_mutations: [],
          coverage_gaps: [],
          unresolved: 0,
          unresolved_results: [],
          unparseable: 0,
          unparseable_results: []
        )
        allow(runner).to receive(:call).and_return(equivalent_summary)

        response = described_class.call(files: ["lib/foo.rb"], verbosity: "full", server_context: nil)

        parsed = JSON.parse(response.content.first[:text])
        equivalent_entry = parsed["equivalent"].first
        expect(equivalent_entry).not_to have_key("diff")
        expect(equivalent_entry["operator"]).to eq("arithmetic_replacement")
      end
    end

    describe "streaming suggestions" do
      let(:subject_obj) do
        instance_double(Evilution::Subject, name: "Foo#bar")
      end

      let(:survived_mutation) do
        instance_double(
          Evilution::Mutation,
          operator_name: "arithmetic_replacement",
          file_path: "lib/foo.rb",
          line: 10,
          diff: "- a + b\n+ a - b",
          unified_diff: nil,
          subject: subject_obj
        )
      end

      let(:survived_result) do
        instance_double(
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
          parent_rss_kb: nil,
          error_message: nil,
          error_class: nil,
          error_backtrace: nil,
          memory_delta_kb: nil
        )
      end

      let(:survived_summary) do
        instance_double(
          Evilution::Result::Summary,
          results: [survived_result],
          total: 1,
          killed: 0,
          survived: 1,
          timed_out: 0,
          errors: 0,
          neutral: 0,
          equivalent: 0,
          score: 0.0,
          duration: 0.5,
          killtime: 0.123,
          efficiency: 0.246,
          mutations_per_second: 2.0,
          truncated?: false,
          survived_results: [survived_result],
          killed_results: [],
          neutral_results: [],
          equivalent_results: [],
          peak_memory_mb: nil,
          skipped: 0,
          disabled_mutations: [],
          coverage_gaps: [],
          unresolved: 0,
          unresolved_results: [],
          unparseable: 0,
          unparseable_results: []
        )
      end

      let(:server_context) do
        # Use a plain double — MCP::ServerContext may not be loaded unless full server is running
        double("server_context", report_progress: nil)
      end

      before do
        allow(runner).to receive(:call).and_return(survived_summary)
      end

      it "sends progress notification for survived mutations when suggest_tests is true" do
        # Capture the on_result callback passed to Runner
        captured_callback = nil
        allow(Evilution::Runner).to receive(:new) do |**kwargs|
          captured_callback = kwargs[:on_result]
          runner
        end

        described_class.call(files: ["lib/foo.rb"], suggest_tests: true, server_context: server_context)

        expect(captured_callback).not_to be_nil

        # Simulate the callback being called with a survived result
        captured_callback.call(survived_result)

        expect(server_context).to have_received(:report_progress) do |index, message:|
          expect(index).to eq(1)
          detail = JSON.parse(message)
          expect(detail["operator"]).to eq("arithmetic_replacement")
          expect(detail["file"]).to eq("lib/foo.rb")
          expect(detail["suggestion"]).to be_a(String)
          expect(detail["suggestion"].length).to be > 0
        end
      end

      it "does not send progress for killed mutations" do
        captured_callback = nil
        allow(Evilution::Runner).to receive(:new) do |**kwargs|
          captured_callback = kwargs[:on_result]
          runner
        end

        described_class.call(files: ["lib/foo.rb"], suggest_tests: true, server_context: server_context)

        captured_callback.call(killed_result)

        expect(server_context).not_to have_received(:report_progress)
      end

      it "does not set callback when suggest_tests is false" do
        captured_callback = nil
        allow(Evilution::Runner).to receive(:new) do |**kwargs|
          captured_callback = kwargs[:on_result]
          runner
        end

        described_class.call(files: ["lib/foo.rb"], suggest_tests: false, server_context: server_context)

        expect(captured_callback).to be_nil
      end

      it "does not set callback when server_context is nil" do
        captured_callback = nil
        allow(Evilution::Runner).to receive(:new) do |**kwargs|
          captured_callback = kwargs[:on_result]
          runner
        end

        described_class.call(files: ["lib/foo.rb"], suggest_tests: true, server_context: nil)

        expect(captured_callback).to be_nil
      end
    end
  end
end

RSpec.describe Evilution::MCP::MutateTool, "feedback hint in tool description" do
  it "mentions the feedback channel" do
    expect(described_class.description).to match(/feedback/i)
  end

  it "mentions evilution-info action=feedback" do
    expect(described_class.description).to include("evilution-info")
    expect(described_class.description).to match(/action[= ]feedback/i)
  end

  it "explicitly tells the agent to ask the user before posting" do
    expect(described_class.description).to match(/ask the user|user permission|user approval/i)
  end
end
