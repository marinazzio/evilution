# frozen_string_literal: true

require "json"
require "tmpdir"
require "evilution/mcp/session_diff_tool"

RSpec.describe Evilution::MCP::SessionDiffTool do
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

  def session_data(score:, total: 10, killed: 8, survived: 2, survivors: [])
    {
      "timestamp" => "2026-03-24T10:00:00+00:00",
      "summary" => {
        "total" => total,
        "killed" => killed,
        "survived" => survived,
        "timed_out" => 0,
        "errors" => 0,
        "neutral" => 0,
        "equivalent" => 0,
        "score" => score,
        "duration" => 5.0
      },
      "survived" => survivors
    }
  end

  def mutation(operator:, file:, line:, subject:)
    { "operator" => operator, "file" => file, "line" => line, "subject" => subject,
      "diff" => "- old\n+ new" }
  end

  let(:mutation_a) { mutation(operator: "arithmetic_replacement", file: "lib/foo.rb", line: 10, subject: "Foo#bar") }
  let(:mutation_b) { mutation(operator: "comparison_replacement", file: "lib/foo.rb", line: 20, subject: "Foo#baz") }
  let(:mutation_c) { mutation(operator: "boolean_replacement", file: "lib/bar.rb", line: 5, subject: "Bar#check") }

  describe "summary comparison" do
    it "returns score change between sessions" do
      base = write_session("base.json", session_data(score: 0.8, survivors: [mutation_a, mutation_b]))
      head = write_session("head.json", session_data(score: 0.9, total: 10, killed: 9, survived: 1,
                                                     survivors: [mutation_a]))

      data = parse_response(call(base: base, head: head))

      expect(data["summary"]["base_score"]).to eq(0.8)
      expect(data["summary"]["head_score"]).to eq(0.9)
      expect(data["summary"]["score_delta"]).to eq(0.1)
    end

    it "returns survived count changes" do
      base = write_session("base.json", session_data(score: 0.8, survivors: [mutation_a, mutation_b]))
      head = write_session("head.json", session_data(score: 0.9, total: 10, killed: 9, survived: 1,
                                                     survivors: [mutation_a]))

      data = parse_response(call(base: base, head: head))

      expect(data["summary"]["base_survived"]).to eq(2)
      expect(data["summary"]["head_survived"]).to eq(1)
    end
  end

  describe "mutation diff" do
    it "identifies fixed mutations (in base but not in head)" do
      base = write_session("base.json", session_data(score: 0.8, survivors: [mutation_a, mutation_b]))
      head = write_session("head.json", session_data(score: 0.9, total: 10, killed: 9, survived: 1,
                                                     survivors: [mutation_a]))

      data = parse_response(call(base: base, head: head))

      expect(data["fixed"].length).to eq(1)
      expect(data["fixed"].first["subject"]).to eq("Foo#baz")
    end

    it "identifies new regressions (in head but not in base)" do
      base = write_session("base.json", session_data(score: 0.9, total: 10, killed: 9, survived: 1,
                                                     survivors: [mutation_a]))
      head = write_session("head.json", session_data(score: 0.7, total: 10, killed: 7, survived: 3,
                                                     survivors: [mutation_a, mutation_b, mutation_c]))

      data = parse_response(call(base: base, head: head))

      expect(data["new_survivors"].length).to eq(2)
      subjects = data["new_survivors"].map { |m| m["subject"] }
      expect(subjects).to contain_exactly("Foo#baz", "Bar#check")
    end

    it "identifies persistent survivors (in both)" do
      base = write_session("base.json", session_data(score: 0.8, survivors: [mutation_a, mutation_b]))
      head = write_session("head.json", session_data(score: 0.8, survivors: [mutation_a, mutation_b]))

      data = parse_response(call(base: base, head: head))

      expect(data["persistent"].length).to eq(2)
    end

    it "returns empty arrays when no mutations change" do
      base = write_session("base.json", session_data(score: 1.0, total: 10, killed: 10, survived: 0, survivors: []))
      head = write_session("head.json", session_data(score: 1.0, total: 10, killed: 10, survived: 0, survivors: []))

      data = parse_response(call(base: base, head: head))

      expect(data["fixed"]).to eq([])
      expect(data["new_survivors"]).to eq([])
      expect(data["persistent"]).to eq([])
    end
  end

  describe "error handling" do
    it "returns error when base is not provided" do
      head = write_session("head.json", session_data(score: 0.8, survivors: []))

      response = call(head: head)

      expect(response.error?).to be true
      expect(response.content.first[:text]).to include("base is required")
    end

    it "returns error when head is not provided" do
      base = write_session("base.json", session_data(score: 0.8, survivors: []))

      response = call(base: base)

      expect(response.error?).to be true
      expect(response.content.first[:text]).to include("head is required")
    end

    it "returns error for non-existent base file" do
      head = write_session("head.json", session_data(score: 0.8, survivors: []))

      response = call(base: "/nonexistent.json", head: head)

      expect(response.error?).to be true
      expect(response.content.first[:text]).to include("session file not found")
    end

    it "returns error for corrupt JSON" do
      base = File.join(results_dir, "base.json")
      File.write(base, "{{{bad")
      head = write_session("head.json", session_data(score: 0.8, survivors: []))

      response = call(base: base, head: head)

      expect(response.error?).to be true
      data = parse_response(response)
      expect(data["error"]["type"]).to eq("parse_error")
    end
  end
end
