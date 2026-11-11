# frozen_string_literal: true

require "json"
require "tmpdir"
require_relative "../../../scripts/lib/benchmark_perf/store"

RSpec.describe BenchmarkPerf::Store do
  around do |example|
    Dir.mktmpdir { |dir| @dir = dir and example.run }
  end

  let(:store) { described_class.new(@dir) }

  def report_json(status)
    JSON.generate("summary" => { "duration" => 1.0, "killtime" => 0.5 },
                  status => [{ "file" => "a.rb", "line" => 1, "operator" => "cmp",
                               "status" => status, "duration" => 0.5, "diff" => "" }])
  end

  it "writes raw output and run metadata per target, version and repeat" do
    store.save(target: "fixture", version: "feature/x", repeat: 2, stdout: "{}", wall: 3.5)

    run_dir = File.join(@dir, "runs", "fixture", "feature_x")
    expect(File.read(File.join(run_dir, "2.json"))).to eq("{}")
    expect(JSON.parse(File.read(File.join(run_dir, "2.meta.json"))))
      .to include("wall" => 3.5, "error" => nil, "version" => "feature/x", "target" => "fixture")
  end

  it "rebuilds samples and metadata from disk" do
    store.save_meta("versions" => %w[A B], "labels" => { "A" => "a1", "B" => "b1" }, "repeats" => 2)
    store.save(target: "fixture", version: "A", repeat: 1, stdout: report_json("killed"), wall: 10.0)
    store.save(target: "fixture", version: "A", repeat: 2, stdout: report_json("killed"), wall: 20.0)
    store.save(target: "fixture", version: "B", repeat: 1, stdout: "garbage", wall: 1.0)

    meta, samples = described_class.new(@dir).load

    expect(meta["labels"]).to eq("A" => "a1", "B" => "b1")
    expect(samples["fixture"]["A"]).to have_attributes(wall_median: 15.0, statuses: { "a.rb:1:cmp" => "killed" })
    expect(samples["fixture"]["B"]).to be_failed
  end

  describe ".run_result" do
    it "treats an evilution error report as a failed run" do
      stdout = JSON.generate("error" => { "type" => "parse_error", "message" => "cannot read lib" })

      result = described_class.run_result(stdout, wall: 0.5)

      expect(result).to have_attributes(failed?: true, error: "evilution parse_error: cannot read lib")
    end
  end

  it "keeps stderr next to the raw output" do
    store.save(target: "fixture", version: "A", repeat: 1, stdout: "", stderr: "LoadError: x\n", wall: 1.0)

    expect(File.read(File.join(@dir, "runs", "fixture", "A", "1.stderr"))).to eq("LoadError: x\n")
  end

  it "fills versions missing from an interrupted run with an empty sample" do
    store.save_meta("versions" => %w[A B], "labels" => {}, "repeats" => 1)
    store.save(target: "fixture", version: "A", repeat: 1, stdout: report_json("killed"), wall: 1.0)

    _, samples = store.load

    expect(samples["fixture"]["B"]).to have_attributes(failed?: true, errors: ["not run"])
  end

  it "keeps a recorded error as a failed run" do
    store.save(target: "fixture", version: "A", repeat: 1, stdout: report_json("killed"), wall: 1.0,
               error: "exit 1: boom")

    _, samples = store.load

    expect(samples["fixture"]["A"].errors).to eq(["exit 1: boom"])
  end
end
