# frozen_string_literal: true

require "json"
require "tmpdir"
require "evilution/mcp/session_show_tool"

RSpec.describe Evilution::MCP::SessionShowTool do
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

  def full_session_data
    {
      "version" => "0.13.0",
      "timestamp" => "2026-03-24T10:00:00+00:00",
      "git" => { "sha" => "abc123def456", "branch" => "main" },
      "summary" => {
        "total" => 10,
        "killed" => 8,
        "survived" => 2,
        "timed_out" => 0,
        "errors" => 0,
        "neutral" => 0,
        "equivalent" => 0,
        "score" => 0.8,
        "duration" => 5.1234
      },
      "survived" => [
        {
          "operator" => "arithmetic_replacement",
          "file" => "lib/foo.rb",
          "line" => 10,
          "subject" => "Foo#bar",
          "diff" => "- a + b\n+ a - b"
        }
      ],
      "killed_count" => 8,
      "timed_out_count" => 0,
      "error_count" => 0,
      "neutral_count" => 0,
      "equivalent_count" => 0
    }
  end

  it "returns a tool response" do
    path = write_session("20260324T100000-aabb0000.json", full_session_data)

    response = call(path: path)

    expect(response).to be_a(MCP::Tool::Response)
  end

  it "returns full session data" do
    path = write_session("20260324T100000-aabb0000.json", full_session_data)

    data = parse_response(call(path: path))

    expect(data["version"]).to eq("0.13.0")
    expect(data["timestamp"]).to eq("2026-03-24T10:00:00+00:00")
    expect(data["summary"]["total"]).to eq(10)
    expect(data["summary"]["score"]).to eq(0.8)
    expect(data["survived"].length).to eq(1)
  end

  it "includes git context" do
    path = write_session("20260324T100000-aabb0000.json", full_session_data)

    data = parse_response(call(path: path))

    expect(data["git"]["sha"]).to eq("abc123def456")
    expect(data["git"]["branch"]).to eq("main")
  end

  it "includes survived mutation details" do
    path = write_session("20260324T100000-aabb0000.json", full_session_data)

    mutation = parse_response(call(path: path))["survived"].first

    expect(mutation["operator"]).to eq("arithmetic_replacement")
    expect(mutation["file"]).to eq("lib/foo.rb")
    expect(mutation["line"]).to eq(10)
    expect(mutation["diff"]).to eq("- a + b\n+ a - b")
  end

  it "returns error for non-existent file" do
    response = call(path: "/nonexistent/session.json")

    expect(response.content.first[:text]).to include("session file not found")
    expect(response.error?).to be true
  end

  it "returns error when path is not provided" do
    response = call

    expect(response.error?).to be true
    expect(response.content.first[:text]).to include("path is required")
  end

  it "returns error for corrupt JSON file" do
    path = File.join(results_dir, "20260324T100000-bad00000.json")
    File.write(path, "{{{invalid")

    response = call(path: path)

    expect(response.error?).to be true
    data = parse_response(response)
    expect(data["error"]["type"]).to eq("parse_error")
  end

  it "returns error for unreadable file" do
    path = File.join(results_dir, "20260324T100000-aabb0000.json")
    File.write(path, "{}")
    File.chmod(0o000, path)

    response = call(path: path)

    expect(response.error?).to be true
    data = parse_response(response)
    expect(data["error"]["type"]).to eq("runtime_error")
  ensure
    File.chmod(0o644, path) if File.exist?(path)
  end
end
