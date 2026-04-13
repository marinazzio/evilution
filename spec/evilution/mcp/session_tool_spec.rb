# frozen_string_literal: true

require "json"
require "tmpdir"
require "evilution/mcp/session_tool"

RSpec.describe Evilution::MCP::SessionTool do
  let(:results_dir) { Dir.mktmpdir("evilution-sessions") }

  after { FileUtils.rm_rf(results_dir) }

  def call(**params)
    described_class.call(server_context: nil, **params)
  end

  def parse_response(response)
    text = response.content.first[:text]
    JSON.parse(text)
  end

  def write_session(filename, data)
    path = File.join(results_dir, filename)
    File.write(path, JSON.generate(data))
    path
  end

  def session_summary(timestamp:, total: 10, killed: 8, survived: 2, score: 0.8, duration: 5.0)
    {
      "timestamp" => timestamp,
      "summary" => {
        "total" => total,
        "killed" => killed,
        "survived" => survived,
        "timed_out" => 0,
        "errors" => 0,
        "neutral" => 0,
        "equivalent" => 0,
        "score" => score,
        "duration" => duration
      },
      "survived" => []
    }
  end

  def mutation(operator:, file:, line:, subject:)
    { "operator" => operator, "file" => file, "line" => line, "subject" => subject,
      "diff" => "- old\n+ new" }
  end

  it "is registered under the evilution-session name" do
    expect(described_class.name_value).to eq("evilution-session")
  end

  describe "action validation" do
    it "returns error when action is missing" do
      response = call

      expect(response.error?).to be true
      expect(response.content.first[:text]).to include("action is required")
    end

    it "returns error when action is unknown" do
      response = call(action: "frobnicate")

      expect(response.error?).to be true
      data = parse_response(response)
      expect(data["error"]["type"]).to eq("config_error")
      expect(data["error"]["message"]).to include("unknown action")
    end
  end

  describe "action: list" do
    it "returns an array of sessions" do
      write_session("20260320T100000-aabb0000.json",
                    session_summary(timestamp: "2026-03-20T10:00:00+00:00"))

      data = parse_response(call(action: "list", results_dir: results_dir))

      expect(data).to be_an(Array)
      expect(data.length).to eq(1)
      expect(data.first["timestamp"]).to eq("2026-03-20T10:00:00+00:00")
    end

    it "returns empty array when no sessions exist" do
      data = parse_response(call(action: "list", results_dir: results_dir))

      expect(data).to eq([])
    end

    it "returns sessions in reverse chronological order" do
      write_session("20260320T100000-aabb0000.json",
                    session_summary(timestamp: "2026-03-20T10:00:00+00:00"))
      write_session("20260321T100000-ccdd0000.json",
                    session_summary(timestamp: "2026-03-21T10:00:00+00:00"))

      data = parse_response(call(action: "list", results_dir: results_dir))

      expect(data.first["timestamp"]).to eq("2026-03-21T10:00:00+00:00")
    end

    it "respects limit parameter" do
      write_session("20260320T100000-aabb0000.json",
                    session_summary(timestamp: "2026-03-20T10:00:00+00:00"))
      write_session("20260321T100000-ccdd0000.json",
                    session_summary(timestamp: "2026-03-21T10:00:00+00:00"))
      write_session("20260322T100000-eeff0000.json",
                    session_summary(timestamp: "2026-03-22T10:00:00+00:00"))

      data = parse_response(call(action: "list", results_dir: results_dir, limit: 2))

      expect(data.length).to eq(2)
      expect(data.first["timestamp"]).to eq("2026-03-22T10:00:00+00:00")
    end

    it "uses default results directory when results_dir is not specified" do
      response = call(action: "list")

      expect(response).to be_a(MCP::Tool::Response)
    end
  end

  describe "action: show" do
    let(:full_session) do
      {
        "version" => "0.22.7",
        "timestamp" => "2026-03-24T10:00:00+00:00",
        "git" => { "sha" => "abc123def456", "branch" => "main" },
        "summary" => {
          "total" => 10, "killed" => 8, "survived" => 2,
          "timed_out" => 0, "errors" => 0, "neutral" => 0, "equivalent" => 0,
          "score" => 0.8, "duration" => 5.12
        },
        "survived" => [mutation(operator: "arithmetic_replacement",
                                file: "lib/foo.rb", line: 10, subject: "Foo#bar")]
      }
    end

    it "returns full session data" do
      path = write_session("20260324T100000-aabb0000.json", full_session)

      data = parse_response(call(action: "show", path: path))

      expect(data["version"]).to eq("0.22.7")
      expect(data["summary"]["score"]).to eq(0.8)
      expect(data["survived"].length).to eq(1)
      expect(data["git"]["sha"]).to eq("abc123def456")
    end

    it "returns error when path is not provided" do
      response = call(action: "show")

      expect(response.error?).to be true
      expect(response.content.first[:text]).to include("path is required")
    end

    it "returns error for non-existent file" do
      response = call(action: "show", path: "/nonexistent/session.json")

      expect(response.error?).to be true
      data = parse_response(response)
      expect(data["error"]["type"]).to eq("not_found")
    end

    it "returns error for corrupt JSON file" do
      path = File.join(results_dir, "bad.json")
      File.write(path, "{{{invalid")

      response = call(action: "show", path: path)

      expect(response.error?).to be true
      data = parse_response(response)
      expect(data["error"]["type"]).to eq("parse_error")
    end
  end

  describe "action: diff" do
    let(:mutation_a) { mutation(operator: "arithmetic_replacement", file: "lib/foo.rb", line: 10, subject: "Foo#bar") }
    let(:mutation_b) { mutation(operator: "comparison_replacement", file: "lib/foo.rb", line: 20, subject: "Foo#baz") }

    def diff_session(score:, survivors:, total: 10, killed: 8, survived: 2)
      session_summary(timestamp: "2026-03-24T10:00:00+00:00",
                      total: total, killed: killed, survived: survived, score: score)
        .merge("survived" => survivors)
    end

    it "returns score delta and mutation diff between sessions" do
      base_path = write_session("base.json",
                                diff_session(score: 0.8, survivors: [mutation_a, mutation_b]))
      head_path = write_session("head.json",
                                diff_session(score: 0.9, total: 10, killed: 9, survived: 1,
                                             survivors: [mutation_a]))

      data = parse_response(call(action: "diff", base: base_path, head: head_path))

      expect(data["summary"]["score_delta"]).to eq(0.1)
      expect(data["fixed"].length).to eq(1)
      expect(data["fixed"].first["subject"]).to eq("Foo#baz")
      expect(data["persistent"].length).to eq(1)
      expect(data["new_survivors"]).to eq([])
    end

    it "returns error when base is not provided" do
      head_path = write_session("head.json", diff_session(score: 0.8, survivors: []))

      response = call(action: "diff", head: head_path)

      expect(response.error?).to be true
      expect(response.content.first[:text]).to include("base is required")
    end

    it "returns error when head is not provided" do
      base_path = write_session("base.json", diff_session(score: 0.8, survivors: []))

      response = call(action: "diff", base: base_path)

      expect(response.error?).to be true
      expect(response.content.first[:text]).to include("head is required")
    end

    it "returns error for non-existent base file" do
      head_path = write_session("head.json", diff_session(score: 0.8, survivors: []))

      response = call(action: "diff", base: "/nonexistent.json", head: head_path)

      expect(response.error?).to be true
      data = parse_response(response)
      expect(data["error"]["type"]).to eq("not_found")
    end
  end
end
