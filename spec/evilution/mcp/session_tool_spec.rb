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

  # Kills EV-t1qg / GH #1192 string_literal on success_response and
  # error_response Response content `type: "text"` — MCP clients dispatch on
  # the type field, so it must be the literal string "text".
  it "wraps every Response payload in a content element typed as 'text'" do
    success = call(action: "list", results_dir: results_dir)
    failure = call

    [success, failure].each do |response|
      element = response.content.first
      expect(element[:type]).to eq("text")
      expect(element[:text]).to be_a(String)
    end
  end

  describe "action validation" do
    it "returns error when action is missing" do
      response = call

      expect(response.error?).to be true
      data = parse_response(response)
      expect(data["error"]["type"]).to eq("config_error")
      expect(data["error"]["message"]).to eq("action is required")
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
    it "returns an envelope containing schema_version and a sessions array" do
      write_session("20260320T100000-aabb0000.json",
                    session_summary(timestamp: "2026-03-20T10:00:00+00:00"))

      data = parse_response(call(action: "list", results_dir: results_dir))

      expect(data).to be_a(Hash)
      expect(data["schema_version"]).to eq(Evilution::MCP::CONTRACT_VERSION)
      expect(data["sessions"]).to be_an(Array)
      expect(data["sessions"].length).to eq(1)
      expect(data["sessions"].first["timestamp"]).to eq("2026-03-20T10:00:00+00:00")
    end

    it "exposes each session entry as a hash with string-keyed summary fields" do
      write_session("20260320T100000-aabb0000.json",
                    session_summary(timestamp: "2026-03-20T10:00:00+00:00",
                                    total: 12, killed: 9, survived: 3, score: 0.75, duration: 4.2))

      data = parse_response(call(action: "list", results_dir: results_dir))
      entry = data["sessions"].first

      expect(entry.keys).to contain_exactly(
        "file", "timestamp", "total", "killed", "survived", "score", "duration"
      )
      expect(entry["total"]).to eq(12)
      expect(entry["killed"]).to eq(9)
      expect(entry["survived"]).to eq(3)
      expect(entry["score"]).to eq(0.75)
      expect(entry["duration"]).to eq(4.2)
      expect(entry["file"]).to end_with("20260320T100000-aabb0000.json")
    end

    it "returns an empty sessions array (still wrapped in envelope) when no sessions exist" do
      data = parse_response(call(action: "list", results_dir: results_dir))

      expect(data["schema_version"]).to eq(Evilution::MCP::CONTRACT_VERSION)
      expect(data["sessions"]).to eq([])
    end

    it "returns sessions in reverse chronological order" do
      write_session("20260320T100000-aabb0000.json",
                    session_summary(timestamp: "2026-03-20T10:00:00+00:00"))
      write_session("20260321T100000-ccdd0000.json",
                    session_summary(timestamp: "2026-03-21T10:00:00+00:00"))

      data = parse_response(call(action: "list", results_dir: results_dir))

      expect(data["sessions"].first["timestamp"]).to eq("2026-03-21T10:00:00+00:00")
    end

    it "respects limit parameter" do
      write_session("20260320T100000-aabb0000.json",
                    session_summary(timestamp: "2026-03-20T10:00:00+00:00"))
      write_session("20260321T100000-ccdd0000.json",
                    session_summary(timestamp: "2026-03-21T10:00:00+00:00"))
      write_session("20260322T100000-eeff0000.json",
                    session_summary(timestamp: "2026-03-22T10:00:00+00:00"))

      data = parse_response(call(action: "list", results_dir: results_dir, limit: 2))

      expect(data["sessions"].length).to eq(2)
      expect(data["sessions"].first["timestamp"]).to eq("2026-03-22T10:00:00+00:00")
    end

    it "uses default results directory when results_dir is not specified" do
      response = call(action: "list")

      expect(response).to be_a(MCP::Tool::Response)
    end

    # Kills EV-t1qg / GH #1192 nil_replacement on the `limit: nil` kwarg
    # default (-> `limit: false`/`0`/`""`/`true`). The default must behave as
    # "missing parameter": absence of `limit:` must not produce a
    # config_error envelope and must not invoke Integer() coercion.
    it "list without an explicit limit returns a successful (non-error) envelope" do
      response = call(action: "list", results_dir: results_dir)

      expect(response.error?).to be(false)
      data = parse_response(response)
      expect(data).not_to have_key("error")
    end

    it "returns a structured error for a negative limit" do
      response = call(action: "list", results_dir: results_dir, limit: -1)

      expect(response.error?).to be true
      data = parse_response(response)
      expect(data["error"]["type"]).to eq("config_error")
      expect(data["error"]["message"]).to include("limit must be a non-negative integer")
    end

    it "returns a structured error for a non-integer limit" do
      response = call(action: "list", results_dir: results_dir, limit: "abc")

      expect(response.error?).to be true
      data = parse_response(response)
      expect(data["error"]["type"]).to eq("config_error")
      expect(data["error"]["message"]).to include("limit must be a non-negative integer")
    end

    it "accepts limit: 0 as a valid (empty) request" do
      write_session("20260320T100000-aabb0000.json",
                    session_summary(timestamp: "2026-03-20T10:00:00+00:00"))

      data = parse_response(call(action: "list", results_dir: results_dir, limit: 0))

      expect(data["sessions"]).to eq([])
    end

    it "coerces integer-like string limit" do
      write_session("20260320T100000-aabb0000.json",
                    session_summary(timestamp: "2026-03-20T10:00:00+00:00"))
      write_session("20260321T100000-ccdd0000.json",
                    session_summary(timestamp: "2026-03-21T10:00:00+00:00"))

      data = parse_response(call(action: "list", results_dir: results_dir, limit: "1"))

      expect(data["sessions"].length).to eq(1)
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

      data = parse_response(call(action: "show", path: path, results_dir: results_dir))

      expect(data["version"]).to eq("0.22.7")
      expect(data["summary"]["score"]).to eq(0.8)
      expect(data["survived"].length).to eq(1)
      expect(data["git"]["sha"]).to eq("abc123def456")
    end

    it "returns error when path is not provided" do
      response = call(action: "show")

      expect(response.error?).to be true
      data = parse_response(response)
      expect(data["error"]["type"]).to eq("config_error")
      expect(data["error"]["message"]).to eq("path is required")
    end

    it "returns error for non-existent file inside results_dir" do
      response = call(action: "show", path: File.join(results_dir, "nope.json"), results_dir: results_dir)

      expect(response.error?).to be true
      data = parse_response(response)
      expect(data["error"]["type"]).to eq("not_found")
      expect(data["error"]["message"]).to include("session file not found")
    end

    it "returns error for corrupt JSON file" do
      path = File.join(results_dir, "bad.json")
      File.write(path, "{{{invalid")

      response = call(action: "show", path: path, results_dir: results_dir)

      expect(response.error?).to be true
      data = parse_response(response)
      expect(data["error"]["type"]).to eq("parse_error")
      expect(data["error"]["message"]).to be_a(String)
      expect(data["error"]["message"]).not_to be_empty
    end

    it "rejects an absolute path outside the results directory" do
      outside = Dir.mktmpdir("evilution-outside")
      outside_path = File.join(outside, "secret.json")
      File.write(outside_path, JSON.generate(full_session))

      response = call(action: "show", path: outside_path, results_dir: results_dir)

      expect(response.error?).to be true
      data = parse_response(response)
      expect(data["error"]["type"]).to eq("config_error")
      expect(data["error"]["message"]).to include("results directory")
    ensure
      FileUtils.rm_rf(outside)
    end

    it "rejects a relative path that escapes the results directory via .." do
      response = call(action: "show",
                      path: File.join(results_dir, "..", "..", "etc", "passwd"),
                      results_dir: results_dir)

      expect(response.error?).to be true
      data = parse_response(response)
      expect(data["error"]["type"]).to eq("config_error")
      expect(data["error"]["message"]).to include("results directory")
    end

    it "rejects a symlink inside results_dir that points outside" do
      outside = Dir.mktmpdir("evilution-outside")
      target = File.join(outside, "secret.json")
      File.write(target, JSON.generate(full_session))
      link_path = File.join(results_dir, "link.json")
      File.symlink(target, link_path)

      response = call(action: "show", path: link_path, results_dir: results_dir)

      expect(response.error?).to be true
      data = parse_response(response)
      expect(data["error"]["type"]).to eq("config_error")
      expect(data["error"]["message"]).to include("results directory")
    ensure
      FileUtils.rm_rf(outside)
    end

    it "does not touch the filesystem for a path outside the boundary" do
      outside_path = "/etc/shadow"

      expect(File).not_to receive(:exist?).with(outside_path)
      expect(File).not_to receive(:read).with(outside_path)

      response = call(action: "show", path: outside_path, results_dir: results_dir)

      expect(response.error?).to be true
      data = parse_response(response)
      expect(data["error"]["type"]).to eq("config_error")
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

      data = parse_response(call(action: "diff", base: base_path, head: head_path, results_dir: results_dir))

      expect(data["summary"]["score_delta"]).to eq(0.1)
      expect(data["fixed"].length).to eq(1)
      expect(data["fixed"].first["subject"]).to eq("Foo#baz")
      expect(data["persistent"].length).to eq(1)
      expect(data["new_survivors"]).to eq([])
    end

    it "includes the MCP contract schema_version on the diff output" do
      base_path = write_session("base.json", diff_session(score: 0.8, survivors: []))
      head_path = write_session("head.json", diff_session(score: 0.9, survivors: []))

      data = parse_response(call(action: "diff", base: base_path, head: head_path, results_dir: results_dir))

      expect(data["schema_version"]).to eq(Evilution::MCP::CONTRACT_VERSION)
    end

    it "returns error when base is not provided" do
      head_path = write_session("head.json", diff_session(score: 0.8, survivors: []))

      response = call(action: "diff", head: head_path, results_dir: results_dir)

      expect(response.error?).to be true
      data = parse_response(response)
      expect(data["error"]["type"]).to eq("config_error")
      expect(data["error"]["message"]).to eq("base is required")
    end

    it "returns error when head is not provided" do
      base_path = write_session("base.json", diff_session(score: 0.8, survivors: []))

      response = call(action: "diff", base: base_path, results_dir: results_dir)

      expect(response.error?).to be true
      data = parse_response(response)
      expect(data["error"]["type"]).to eq("config_error")
      expect(data["error"]["message"]).to eq("head is required")
    end

    it "returns error for non-existent base file inside results_dir" do
      head_path = write_session("head.json", diff_session(score: 0.8, survivors: []))

      response = call(action: "diff",
                      base: File.join(results_dir, "missing.json"),
                      head: head_path,
                      results_dir: results_dir)

      expect(response.error?).to be true
      data = parse_response(response)
      expect(data["error"]["type"]).to eq("not_found")
      expect(data["error"]["message"]).to include("session file not found")
    end

    # Kills EV-t1qg / GH #1192 string_literal + argument_nil_substitution on
    # the parse_error branch of diff_action — neither the error type nor the
    # underlying parser message has a regression spec without this.
    it "returns a parse_error envelope when one of the diff sessions is malformed JSON" do
      base_path = File.join(results_dir, "bad_base.json")
      File.write(base_path, "{{{invalid")
      head_path = write_session("head.json", diff_session(score: 0.8, survivors: []))

      response = call(action: "diff", base: base_path, head: head_path, results_dir: results_dir)

      expect(response.error?).to be true
      data = parse_response(response)
      expect(data["error"]["type"]).to eq("parse_error")
      expect(data["error"]["message"]).to be_a(String)
      expect(data["error"]["message"]).not_to be_empty
    end

    # Kills EV-t1qg / GH #1192 string_literal + argument_removal +
    # argument_nil_substitution on the runtime_error branches of show/diff —
    # SystemCallError is converted to a structured runtime_error envelope
    # with the OS message preserved.
    it "returns a runtime_error envelope when reading a session raises SystemCallError" do
      base_path = write_session("base.json", diff_session(score: 0.8, survivors: []))
      head_path = write_session("head.json", diff_session(score: 0.8, survivors: []))
      allow_any_instance_of(Evilution::Session::Store)
        .to receive(:load).and_raise(Errno::EIO, "disk on fire")

      response = call(action: "diff", base: base_path, head: head_path, results_dir: results_dir)

      expect(response.error?).to be true
      data = parse_response(response)
      expect(data["error"]["type"]).to eq("runtime_error")
      expect(data["error"]["message"]).to include("disk on fire")
    end

    it "returns a runtime_error envelope for show when reading the session raises SystemCallError" do
      path = write_session("ok.json", session_summary(timestamp: "2026-03-20T10:00:00+00:00"))
      allow_any_instance_of(Evilution::Session::Store)
        .to receive(:load).and_raise(Errno::EIO, "disk on fire")

      response = call(action: "show", path: path, results_dir: results_dir)

      expect(response.error?).to be true
      data = parse_response(response)
      expect(data["error"]["type"]).to eq("runtime_error")
      expect(data["error"]["message"]).to include("disk on fire")
    end

    it "rejects base path outside the results directory" do
      outside = Dir.mktmpdir("evilution-outside")
      outside_path = File.join(outside, "base.json")
      File.write(outside_path, JSON.generate(diff_session(score: 0.8, survivors: [])))
      head_path = write_session("head.json", diff_session(score: 0.8, survivors: []))

      response = call(action: "diff", base: outside_path, head: head_path, results_dir: results_dir)

      expect(response.error?).to be true
      data = parse_response(response)
      expect(data["error"]["type"]).to eq("config_error")
      expect(data["error"]["message"]).to include("results directory")
    ensure
      FileUtils.rm_rf(outside)
    end

    it "rejects head path outside the results directory" do
      outside = Dir.mktmpdir("evilution-outside")
      outside_path = File.join(outside, "head.json")
      File.write(outside_path, JSON.generate(diff_session(score: 0.8, survivors: [])))
      base_path = write_session("base.json", diff_session(score: 0.8, survivors: []))

      response = call(action: "diff", base: base_path, head: outside_path, results_dir: results_dir)

      expect(response.error?).to be true
      data = parse_response(response)
      expect(data["error"]["type"]).to eq("config_error")
      expect(data["error"]["message"]).to include("results directory")
    ensure
      FileUtils.rm_rf(outside)
    end
  end
end
