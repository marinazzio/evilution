# frozen_string_literal: true

require "json"
require "evilution/mcp/info_tool"
require "evilution/version"

RSpec.describe Evilution::MCP::InfoTool do
  def call(**params)
    described_class.call(server_context: nil, **params)
  end

  def parse_response(response)
    JSON.parse(response.content.first[:text])
  end

  it "is registered under the evilution-info name" do
    expect(described_class.name_value).to eq("evilution-info")
  end

  describe "action validation" do
    it "returns error when action is missing" do
      response = call

      expect(response.error?).to be true
      data = parse_response(response)
      expect(data["error"]["type"]).to eq("config_error")
      expect(data["error"]["message"]).to include("action is required")
    end

    it "returns error when action is unknown" do
      response = call(action: "frobnicate")

      expect(response.error?).to be true
      data = parse_response(response)
      expect(data["error"]["type"]).to eq("config_error")
      expect(data["error"]["message"]).to include("unknown action")
    end
  end

  describe "action: subjects" do
    let(:fixture) { "spec/support/fixtures/arithmetic.rb" }

    it "returns subjects for the given files with mutation counts" do
      data = parse_response(call(action: "subjects", files: [fixture]))

      expect(data).to be_a(Hash)
      expect(data["subjects"]).to be_an(Array)
      expect(data["subjects"]).not_to be_empty

      names = data["subjects"].map { |s| s["name"] }
      expect(names).to include("Calculator#add", "Calculator#subtract", "Calculator#multiply")
    end

    it "includes file, line, and mutations fields per subject" do
      data = parse_response(call(action: "subjects", files: [fixture]))

      entry = data["subjects"].find { |s| s["name"] == "Calculator#add" }
      expect(entry["file"]).to eq(fixture)
      expect(entry["line"]).to be_a(Integer)
      expect(entry["mutations"]).to be_a(Integer)
      expect(entry["mutations"]).to be > 0
    end

    it "includes total_subjects and total_mutations" do
      data = parse_response(call(action: "subjects", files: [fixture]))

      expect(data["total_subjects"]).to eq(data["subjects"].length)
      expect(data["total_mutations"]).to eq(data["subjects"].sum { |s| s["mutations"] })
    end

    it "returns an empty result when no subjects found" do
      tmp = Tempfile.new(["empty", ".rb"])
      tmp.write("# just a comment\n")
      tmp.close

      data = parse_response(call(action: "subjects", files: [tmp.path]))

      expect(data["subjects"]).to eq([])
      expect(data["total_subjects"]).to eq(0)
      expect(data["total_mutations"]).to eq(0)
    ensure
      tmp&.unlink
    end

    it "returns error when files is missing" do
      response = call(action: "subjects")

      expect(response.error?).to be true
      expect(response.content.first[:text]).to include("files is required")
    end

    it "returns error when files is empty" do
      response = call(action: "subjects", files: [])

      expect(response.error?).to be true
      expect(response.content.first[:text]).to include("files is required")
    end

    it "applies the target filter" do
      data = parse_response(call(action: "subjects", files: [fixture], target: "Calculator#add"))

      names = data["subjects"].map { |s| s["name"] }
      expect(names).to eq(["Calculator#add"])
    end

    it "parses line-range syntax in files and narrows subjects to that range" do
      data = parse_response(call(action: "subjects", files: ["#{fixture}:2-4"]))

      names = data["subjects"].map { |s| s["name"] }
      expect(names).to eq(["Calculator#add"])
    end

    it "returns a parse_error for an invalid line range" do
      response = call(action: "subjects", files: ["#{fixture}:notanumber"])

      expect(response.error?).to be true
      data = parse_response(response)
      expect(data["error"]["type"]).to eq("parse_error")
      expect(data["error"]["message"]).to include("invalid line range")
    end

    context "config file handling" do
      let(:fixture_contents) { File.read(File.expand_path("../../support/fixtures/arithmetic.rb", __dir__)) }

      around do |example|
        contents = fixture_contents
        Dir.mktmpdir do |dir|
          Dir.chdir(dir) do
            FileUtils.mkdir_p("lib")
            File.write("lib/arithmetic.rb", contents)
            example.run
          end
        end
      end

      it "applies target from .evilution.yml" do
        File.write(".evilution.yml", "target: Calculator#add\n")

        data = parse_response(call(action: "subjects", files: ["lib/arithmetic.rb"]))

        names = data["subjects"].map { |s| s["name"] }
        expect(names).to eq(["Calculator#add"])
      end

      it "ignores .evilution.yml when skip_config is true" do
        File.write(".evilution.yml", "target: Calculator#add\n")

        data = parse_response(call(action: "subjects", files: ["lib/arithmetic.rb"], skip_config: true))

        names = data["subjects"].map { |s| s["name"] }
        expect(names).to include("Calculator#add", "Calculator#subtract", "Calculator#multiply")
      end
    end
  end

  describe "action: tests" do
    it "resolves spec files for the given sources" do
      data = parse_response(call(action: "tests", files: ["lib/evilution/subject.rb"]))

      expect(data).to be_a(Hash)
      expect(data["specs"]).to be_an(Array)
      entry = data["specs"].find { |s| s["source"] == "lib/evilution/subject.rb" }
      expect(entry).not_to be_nil
      expect(entry["spec"]).to eq("spec/evilution/subject_spec.rb")
    end

    it "reports sources with no matching spec under unresolved" do
      data = parse_response(call(action: "tests", files: ["lib/totally_bogus_xyz_abc/file.rb"]))

      expect(data["unresolved"]).to include("lib/totally_bogus_xyz_abc/file.rb")
      expect(data["specs"]).to eq([])
    end

    it "includes total_sources and total_specs counts" do
      data = parse_response(call(action: "tests", files: ["lib/evilution/subject.rb"]))

      expect(data["total_sources"]).to eq(1)
      expect(data["total_specs"]).to eq(1)
    end

    it "honors explicit spec overrides" do
      data = parse_response(call(action: "tests", files: ["lib/evilution/subject.rb"],
                                 spec: ["spec/custom_spec.rb"]))

      expect(data["specs"].map { |s| s["spec"] }).to eq(["spec/custom_spec.rb"])
    end

    it "uses the minitest resolver when integration is minitest" do
      data = parse_response(call(action: "tests", files: ["lib/evilution/subject.rb"],
                                 integration: "minitest"))

      expect(data["specs"]).to eq([])
      expect(data["unresolved"]).to eq(["lib/evilution/subject.rb"])
    end

    it "strips line-range suffixes from file paths before resolving" do
      data = parse_response(call(action: "tests", files: ["lib/evilution/subject.rb:10-20"]))

      entry = data["specs"].find { |s| s["source"] == "lib/evilution/subject.rb" }
      expect(entry).not_to be_nil
      expect(entry["spec"]).to eq("spec/evilution/subject_spec.rb")
    end

    it "returns error when files is missing" do
      response = call(action: "tests")

      expect(response.error?).to be true
      expect(response.content.first[:text]).to include("files is required")
    end
  end

  describe "action: environment" do
    it "returns version, ruby, and config_file" do
      data = parse_response(call(action: "environment"))

      expect(data["version"]).to eq(Evilution::VERSION)
      expect(data["ruby"]).to eq(RUBY_VERSION)
      expect(data).to have_key("config_file")
    end

    it "returns effective settings" do
      data = parse_response(call(action: "environment"))

      settings = data["settings"]
      expect(settings).to be_a(Hash)
      expect(settings).to include("timeout", "integration", "jobs", "isolation",
                                  "baseline", "incremental", "fail_fast", "min_score",
                                  "suggest_tests", "save_session", "skip_heredoc_literals")
    end

    it "accepts no parameters" do
      response = call(action: "environment")

      expect(response).to be_a(MCP::Tool::Response)
      expect(response.error?).to be_falsey
    end
  end

  describe "action: statuses" do
    it "returns an entry for every STATUSES value" do
      data = parse_response(call(action: "statuses"))

      expected = Evilution::Result::MutationResult::STATUSES.map(&:to_s).sort
      actual = data["statuses"].map { |s| s["status"] }.sort
      expect(actual).to eq(expected)
    end

    it "describes each status with meaning and scoring fields" do
      data = parse_response(call(action: "statuses"))

      data["statuses"].each do |entry|
        expect(entry).to include("status", "meaning", "counted_in_score")
        expect(entry["meaning"]).to be_a(String).and(satisfy { |s| !s.empty? })
        expect([true, false]).to include(entry["counted_in_score"])
      end
    end

    it "marks killed and survived as counted in score" do
      data = parse_response(call(action: "statuses"))
      by_status = data["statuses"].to_h { |s| [s["status"], s] }

      expect(by_status["killed"]["counted_in_score"]).to be true
      expect(by_status["survived"]["counted_in_score"]).to be true
    end

    it "marks neutral, error, equivalent, unresolved, unparseable as excluded from score" do
      data = parse_response(call(action: "statuses"))
      by_status = data["statuses"].to_h { |s| [s["status"], s] }

      %w[neutral error equivalent unresolved unparseable].each do |status|
        expect(by_status[status]["counted_in_score"]).to be(false), "#{status} should be excluded"
      end
    end

    it "distinguishes neutral from error from unresolved in meaning text" do
      data = parse_response(call(action: "statuses"))
      by_status = data["statuses"].to_h { |s| [s["status"], s] }

      expect(by_status["neutral"]["meaning"]).to match(/baseline|pre-existing|infra/i)
      expect(by_status["error"]["meaning"]).to match(/error|crash|unexpected/i)
      expect(by_status["unresolved"]["meaning"]).to match(/spec|resolve|coverage/i)
    end

    it "accepts no parameters" do
      response = call(action: "statuses")

      expect(response).to be_a(MCP::Tool::Response)
      expect(response.error?).to be_falsey
    end
  end
end
