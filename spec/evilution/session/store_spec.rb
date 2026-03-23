# frozen_string_literal: true

require "json"
require "tmpdir"
require "evilution/session/store"

RSpec.describe Evilution::Session::Store do
  let(:results_dir) { Dir.mktmpdir("evilution-sessions") }
  let(:store) { described_class.new(results_dir: results_dir) }

  after { FileUtils.rm_rf(results_dir) }

  def build_mutation(operator: "arithmetic_replacement", file: "lib/foo.rb", line: 5)
    double(
      "Mutation",
      operator_name: operator,
      file_path: file,
      line: line,
      diff: "- a + b\n+ a - b",
      subject: double("Subject", name: "Foo#bar")
    )
  end

  def build_result(mutation, status: :killed, duration: 0.1)
    Evilution::Result::MutationResult.new(
      mutation: mutation,
      status: status,
      duration: duration
    )
  end

  def build_summary(results: [], duration: 1.5)
    Evilution::Result::Summary.new(results: results, duration: duration)
  end

  describe "#save" do
    it "creates a JSON file in the results directory" do
      summary = build_summary

      store.save(summary)

      files = Dir.glob(File.join(results_dir, "*.json"))
      expect(files.length).to eq(1)
    end

    it "stores valid JSON" do
      mutation = build_mutation
      result = build_result(mutation)
      summary = build_summary(results: [result], duration: 2.3)

      store.save(summary)

      file = Dir.glob(File.join(results_dir, "*.json")).first
      data = JSON.parse(File.read(file))
      expect(data).to be_a(Hash)
    end

    it "includes version and timestamp in ISO 8601 format" do
      summary = build_summary

      store.save(summary)

      data = read_saved_session
      expect(data["version"]).to eq(Evilution::VERSION)
      expect(data["timestamp"]).to match(/\A\d{4}-\d{2}-\d{2}T/)
    end

    it "includes all summary statistics" do
      mutation = build_mutation
      killed = build_result(mutation, status: :killed, duration: 0.1)
      survived = build_result(mutation, status: :survived, duration: 0.2)
      timed_out = build_result(mutation, status: :timeout, duration: 30.0)
      errored = build_result(mutation, status: :error, duration: 0.01)
      neutral = build_result(mutation, status: :neutral, duration: 0.05)
      equivalent = build_result(mutation, status: :equivalent, duration: 0.0)
      summary = build_summary(
        results: [killed, survived, timed_out, errored, neutral, equivalent],
        duration: 3.1234567
      )

      store.save(summary)

      data = read_saved_session
      s = data["summary"]
      expect(s["total"]).to eq(6)
      expect(s["killed"]).to eq(1)
      expect(s["survived"]).to eq(1)
      expect(s["timed_out"]).to eq(1)
      expect(s["errors"]).to eq(1)
      expect(s["neutral"]).to eq(1)
      expect(s["equivalent"]).to eq(1)
      expect(s["score"]).to be_a(Float)
      expect(s["score"]).to eq(summary.score.round(4))
      expect(s["duration"]).to eq(3.1235)
    end

    it "includes top-level status counts" do
      mutation = build_mutation
      killed = build_result(mutation, status: :killed)
      timed_out = build_result(mutation, status: :timeout)
      errored = build_result(mutation, status: :error)
      neutral = build_result(mutation, status: :neutral)
      equivalent = build_result(mutation, status: :equivalent)
      summary = build_summary(results: [killed, timed_out, errored, neutral, equivalent])

      store.save(summary)

      data = read_saved_session
      expect(data["killed_count"]).to eq(1)
      expect(data["timed_out_count"]).to eq(1)
      expect(data["error_count"]).to eq(1)
      expect(data["neutral_count"]).to eq(1)
      expect(data["equivalent_count"]).to eq(1)
    end

    it "includes survived mutation details with subject and diff" do
      mutation = build_mutation(operator: "comparison_replacement", file: "lib/bar.rb", line: 10)
      result = build_result(mutation, status: :survived)
      summary = build_summary(results: [result])

      store.save(summary)

      data = read_saved_session
      expect(data["survived"].length).to eq(1)
      entry = data["survived"].first
      expect(entry["operator"]).to eq("comparison_replacement")
      expect(entry["file"]).to eq("lib/bar.rb")
      expect(entry["line"]).to eq(10)
      expect(entry["subject"]).to eq("Foo#bar")
      expect(entry["diff"]).to eq("- a + b\n+ a - b")
    end

    it "excludes killed mutations from survived list" do
      mutation = build_mutation
      result = build_result(mutation, status: :killed)
      summary = build_summary(results: [result])

      store.save(summary)

      data = read_saved_session
      expect(data["survived"]).to eq([])
    end

    it "includes git sha and branch as non-nil trimmed strings in a git repo" do
      summary = build_summary

      store.save(summary)

      data = read_saved_session
      expect(data["git"]["sha"]).to be_a(String)
      expect(data["git"]["sha"]).not_to be_empty
      expect(data["git"]["sha"]).to match(/\A[0-9a-f]{40}\z/)
      expect(data["git"]["branch"]).to be_a(String)
      expect(data["git"]["branch"]).not_to be_empty
      expect(data["git"]["branch"]).not_to match(/\s/)
    end

    it "uses timestamp-hyphen-hex filename format" do
      summary = build_summary

      store.save(summary)

      file = Dir.glob(File.join(results_dir, "*.json")).first
      basename = File.basename(file, ".json")
      expect(basename).to match(/\A\d{8}T\d{6}-[0-9a-f]{8}\z/)
    end

    it "creates the results directory if it does not exist" do
      nested_dir = File.join(results_dir, "nested", "results")
      nested_store = described_class.new(results_dir: nested_dir)
      summary = build_summary

      nested_store.save(summary)

      expect(Dir.exist?(nested_dir)).to be true
      expect(Dir.glob(File.join(nested_dir, "*.json")).length).to eq(1)
    end

    it "returns the path to the saved file" do
      summary = build_summary

      path = store.save(summary)

      expect(path).to end_with(".json")
      expect(File.exist?(path)).to be true
    end

    it "rounds score to 4 decimal places" do
      mutation = build_mutation
      killed1 = build_result(mutation, status: :killed)
      killed2 = build_result(mutation, status: :killed)
      survived = build_result(mutation, status: :survived)
      summary = build_summary(results: [killed1, killed2, survived])

      store.save(summary)

      data = read_saved_session
      expect(data["summary"]["score"]).to eq(0.6667)
    end

    it "rounds duration to 4 decimal places" do
      summary = build_summary(duration: 1.23456789)

      store.save(summary)

      data = read_saved_session
      expect(data["summary"]["duration"]).to eq(1.2346)
    end
  end

  describe "#list" do
    it "returns empty array when no sessions exist" do
      expect(store.list).to eq([])
    end

    it "returns empty array when results directory does not exist" do
      nonexistent_store = described_class.new(results_dir: File.join(results_dir, "nonexistent"))

      expect(nonexistent_store.list).to eq([])
    end

    it "returns session metadata sorted by filename descending" do
      summary_hash = lambda do |total|
        { "total" => total, "killed" => 1, "survived" => 0, "score" => 1.0, "duration" => 1.0 }
      end
      early_data = { "timestamp" => "2026-01-01T00:00:00", "summary" => summary_hash.call(1) }
      late_data = { "timestamp" => "2026-02-01T00:00:00", "summary" => summary_hash.call(2) }

      File.write(File.join(results_dir, "20260101T000000-aaaa0000.json"), JSON.generate(early_data))
      File.write(File.join(results_dir, "20260201T000000-bbbb0000.json"), JSON.generate(late_data))

      sessions = store.list

      expect(sessions.length).to eq(2)
      expect(sessions.first[:total]).to eq(2)
      expect(sessions.last[:total]).to eq(1)
    end

    it "includes all summary fields in each entry" do
      mutation = build_mutation
      killed = build_result(mutation, status: :killed)
      survived = build_result(mutation, status: :survived)
      summary = build_summary(results: [killed, survived], duration: 1.5)
      store.save(summary)

      sessions = store.list

      entry = sessions.first
      expect(entry[:total]).to eq(2)
      expect(entry[:killed]).to eq(1)
      expect(entry[:survived]).to eq(1)
      expect(entry[:score]).to eq(0.5)
      expect(entry[:duration]).to be_within(0.01).of(1.5)
      expect(entry[:file]).to be_a(String)
      expect(entry[:file]).to end_with(".json")
      expect(entry[:timestamp]).to be_a(String)
    end
  end

  describe "#load" do
    it "returns parsed session data with all fields" do
      mutation = build_mutation
      survived = build_result(mutation, status: :survived)
      killed = build_result(mutation, status: :killed)
      summary = build_summary(results: [survived, killed], duration: 2.0)
      path = store.save(summary)

      data = store.load(path)

      expect(data["version"]).to eq(Evilution::VERSION)
      expect(data["timestamp"]).to be_a(String)
      expect(data["git"]).to be_a(Hash)
      expect(data["summary"]["total"]).to eq(2)
      expect(data["summary"]["killed"]).to eq(1)
      expect(data["summary"]["survived"]).to eq(1)
      expect(data["survived"].length).to eq(1)
      expect(data["killed_count"]).to eq(1)
    end

    it "raises an error with descriptive message for non-existent file" do
      expect { store.load("/nonexistent/path.json") }.to raise_error(
        Evilution::Error, "session file not found: /nonexistent/path.json"
      )
    end
  end

  private

  def read_saved_session
    file = Dir.glob(File.join(results_dir, "*.json")).first
    JSON.parse(File.read(file))
  end
end
