# frozen_string_literal: true

require "json"
require "tmpdir"
require "evilution/mcp/session_list_tool"

RSpec.describe Evilution::MCP::SessionListTool do
  let(:results_dir) { Dir.mktmpdir("evilution-sessions") }

  after { FileUtils.rm_rf(results_dir) }

  def call(**params)
    described_class.call(server_context: nil, results_dir: results_dir, **params)
  end

  def parse_response(response)
    text = response.content.first[:text]
    JSON.parse(text)
  end

  def write_session(filename, data)
    File.write(File.join(results_dir, filename), JSON.generate(data))
  end

  def session_data(timestamp:, total: 10, killed: 8, survived: 2, score: 0.8, duration: 5.0)
    {
      "timestamp" => timestamp,
      "summary" => {
        "total" => total,
        "killed" => killed,
        "survived" => survived,
        "score" => score,
        "duration" => duration
      }
    }
  end

  it "returns a tool response" do
    response = call
    expect(response).to be_a(MCP::Tool::Response)
  end

  it "returns an array of sessions" do
    write_session("20260320T100000-aabb0000.json",
                  session_data(timestamp: "2026-03-20T10:00:00+00:00"))

    data = parse_response(call)

    expect(data).to be_an(Array)
    expect(data.length).to eq(1)
  end

  it "returns empty array when no sessions exist" do
    data = parse_response(call)

    expect(data).to eq([])
  end

  it "includes session metadata in each entry" do
    write_session("20260320T100000-aabb0000.json",
                  session_data(timestamp: "2026-03-20T10:00:00+00:00", total: 15, killed: 12,
                               survived: 3, score: 0.8, duration: 4.5))

    entry = parse_response(call).first

    expect(entry["timestamp"]).to eq("2026-03-20T10:00:00+00:00")
    expect(entry["total"]).to eq(15)
    expect(entry["killed"]).to eq(12)
    expect(entry["survived"]).to eq(3)
    expect(entry["score"]).to eq(0.8)
    expect(entry["duration"]).to eq(4.5)
  end

  it "includes file path in each entry" do
    write_session("20260320T100000-aabb0000.json",
                  session_data(timestamp: "2026-03-20T10:00:00+00:00"))

    entry = parse_response(call).first

    expect(entry["file"]).to include("20260320T100000-aabb0000.json")
  end

  it "returns sessions in reverse chronological order" do
    write_session("20260320T100000-aabb0000.json",
                  session_data(timestamp: "2026-03-20T10:00:00+00:00"))
    write_session("20260321T100000-ccdd0000.json",
                  session_data(timestamp: "2026-03-21T10:00:00+00:00"))

    data = parse_response(call)

    expect(data.first["timestamp"]).to eq("2026-03-21T10:00:00+00:00")
    expect(data.last["timestamp"]).to eq("2026-03-20T10:00:00+00:00")
  end

  it "respects limit parameter" do
    write_session("20260320T100000-aabb0000.json",
                  session_data(timestamp: "2026-03-20T10:00:00+00:00"))
    write_session("20260321T100000-ccdd0000.json",
                  session_data(timestamp: "2026-03-21T10:00:00+00:00"))
    write_session("20260322T100000-eeff0000.json",
                  session_data(timestamp: "2026-03-22T10:00:00+00:00"))

    data = parse_response(call(limit: 2))

    expect(data.length).to eq(2)
    expect(data.first["timestamp"]).to eq("2026-03-22T10:00:00+00:00")
  end

  it "returns all sessions when limit is not specified" do
    write_session("20260320T100000-aabb0000.json",
                  session_data(timestamp: "2026-03-20T10:00:00+00:00"))
    write_session("20260321T100000-ccdd0000.json",
                  session_data(timestamp: "2026-03-21T10:00:00+00:00"))

    data = parse_response(call)

    expect(data.length).to eq(2)
  end

  it "uses default results directory when results_dir is not specified" do
    response = described_class.call(server_context: nil)

    expect(response).to be_a(MCP::Tool::Response)
  end
end
