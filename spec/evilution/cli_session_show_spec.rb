# frozen_string_literal: true

require "json"
require "tmpdir"
require "evilution/cli"
require "evilution/session/store"

RSpec.describe Evilution::CLI, "session show" do
  let(:results_dir) { Dir.mktmpdir("evilution-sessions") }

  after { FileUtils.rm_rf(results_dir) }

  def capture_stdout
    io = StringIO.new
    original = $stdout
    $stdout = io
    yield
    io.string
  ensure
    $stdout = original
  end

  def capture_stderr
    io = StringIO.new
    original = $stderr
    $stderr = io
    yield
    io.string
  ensure
    $stderr = original
  end

  def write_session_file(dir, filename, data)
    path = File.join(dir, filename)
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
        },
        {
          "operator" => "comparison_replacement",
          "file" => "lib/foo.rb",
          "line" => 20,
          "subject" => "Foo#baz",
          "diff" => "- x > y\n+ x >= y"
        }
      ],
      "killed_count" => 8,
      "timed_out_count" => 0,
      "error_count" => 0,
      "neutral_count" => 0,
      "equivalent_count" => 0
    }
  end

  describe "session show command" do
    it "returns exit code 0 for a valid session file" do
      path = write_session_file(results_dir, "20260324T100000-aabb0000.json", full_session_data)
      cli = described_class.new(["session", "show", path])
      result = nil
      capture_stdout { result = cli.call }
      expect(result).to eq(0)
    end

    it "displays session summary" do
      path = write_session_file(results_dir, "20260324T100000-aabb0000.json", full_session_data)
      cli = described_class.new(["session", "show", path])
      output = capture_stdout { cli.call }

      expect(output).to include("2026-03-24T10:00:00+00:00")
      expect(output).to include("0.13.0")
      expect(output).to include("80.00%")
      expect(output).to include("10")
      expect(output).to include("5.1")
    end

    it "displays git context" do
      path = write_session_file(results_dir, "20260324T100000-aabb0000.json", full_session_data)
      cli = described_class.new(["session", "show", path])
      output = capture_stdout { cli.call }

      expect(output).to include("abc123def456")
      expect(output).to include("main")
    end

    it "displays survived mutations with diffs" do
      path = write_session_file(results_dir, "20260324T100000-aabb0000.json", full_session_data)
      cli = described_class.new(["session", "show", path])
      output = capture_stdout { cli.call }

      expect(output).to include("arithmetic_replacement")
      expect(output).to include("lib/foo.rb:10")
      expect(output).to include("Foo#bar")
      expect(output).to include("- a + b")
      expect(output).to include("+ a - b")
      expect(output).to include("comparison_replacement")
      expect(output).to include("lib/foo.rb:20")
    end

    it "shows a message when there are no survived mutations" do
      data = full_session_data.merge("survived" => [],
                                     "summary" => full_session_data["summary"].merge("survived" => 0, "score" => 1.0))
      path = write_session_file(results_dir, "20260324T100000-aabb0000.json", data)
      cli = described_class.new(["session", "show", path])
      output = capture_stdout { cli.call }

      expect(output).to include("100.00%")
      expect(output).to include("No survived mutations")
    end

    it "returns exit code 2 for non-existent file" do
      cli = described_class.new(["session", "show", "/nonexistent/path.json"])
      result = nil
      capture_stderr { result = cli.call }
      expect(result).to eq(2)
    end

    it "prints error for non-existent file" do
      cli = described_class.new(["session", "show", "/nonexistent/path.json"])
      output = capture_stderr { cli.call }
      expect(output).to include("session file not found")
    end

    it "returns exit code 2 when no path is given" do
      cli = described_class.new(%w[session show])
      result = nil
      capture_stderr { result = cli.call }
      expect(result).to eq(2)
    end

    it "prints error when no path is given" do
      cli = described_class.new(%w[session show])
      output = capture_stderr { cli.call }
      expect(output).to include("session file path required")
    end

    it "supports --format json to output raw session data" do
      path = write_session_file(results_dir, "20260324T100000-aabb0000.json", full_session_data)
      cli = described_class.new(["session", "show", "--format", "json", path])
      output = capture_stdout { cli.call }
      parsed = JSON.parse(output)

      expect(parsed["version"]).to eq("0.13.0")
      expect(parsed["summary"]["total"]).to eq(10)
      expect(parsed["survived"].length).to eq(2)
    end
  end
end
