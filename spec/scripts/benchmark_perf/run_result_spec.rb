# frozen_string_literal: true

require "digest"
require_relative "../../../scripts/lib/benchmark_perf/run_result"

RSpec.describe BenchmarkPerf::RunResult do
  def detail(file:, line:, operator:, status:, duration:, diff: "- x\n+ y\n")
    { "file" => file, "line" => line, "operator" => operator,
      "status" => status, "duration" => duration, "diff" => diff }
  end

  describe "BenchmarkPerf.mutation_key" do
    it "joins file, line and operator with a short digest of the diff" do
      d = detail(file: "lib/a.rb", line: 3, operator: "cmp", status: "killed", duration: 0.1)
      digest = Digest::SHA256.hexdigest("- x\n+ y\n")[0, 8]

      expect(BenchmarkPerf.mutation_key(d)).to eq("lib/a.rb:3:cmp##{digest}")
    end

    it "drops the digest when the diff is empty" do
      d = detail(file: "lib/a.rb", line: 3, operator: "cmp", status: "killed", duration: 0.1, diff: "")

      expect(BenchmarkPerf.mutation_key(d)).to eq("lib/a.rb:3:cmp")
    end
  end

  describe "BenchmarkPerf.extract_json" do
    it "parses a clean JSON document" do
      expect(BenchmarkPerf.extract_json('{"summary":{}}')).to eq("summary" => {})
    end

    it "skips noise printed before the JSON report" do
      expect(BenchmarkPerf.extract_json("warning: foo\n{\"summary\":{}}\n")).to eq("summary" => {})
    end

    it "skips noise printed after the JSON report" do
      stdout = "{\"summary\":{}}\nCoverage report generated for RSpec to coverage/.\n"

      expect(BenchmarkPerf.extract_json(stdout)).to eq("summary" => {})
    end

    it "skips a noise line that looks like a hash before the report" do
      expect(BenchmarkPerf.extract_json("{:preload=>1}\n{\"summary\":{}}\n")).to eq("summary" => {})
    end

    it "raises ParseError when the output is JSON but not an object" do
      expect { BenchmarkPerf.extract_json("null") }.to raise_error(BenchmarkPerf::ParseError)
    end

    it "raises ParseError when no JSON can be found" do
      expect { BenchmarkPerf.extract_json("boom") }.to raise_error(BenchmarkPerf::ParseError)
    end
  end

  describe ".from_json" do
    let(:data) do
      {
        "summary" => { "duration" => 9.0, "killtime" => 0.95 },
        "killed" => [
          detail(file: "lib/a.rb", line: 1, operator: "cmp", status: "killed", duration: 0.5),
          detail(file: "lib/a.rb", line: 2, operator: "cmp", status: "killed", duration: 0.25)
        ],
        "survived" => [detail(file: "lib/a.rb", line: 3, operator: "lit", status: "survived", duration: 0.2)]
      }
    end

    it "summarises mutants, operators and statuses" do
      result = described_class.from_json(data, wall: 12.0)

      expect(result).to have_attributes(
        mutant_count: 3, wall: 12.0, duration: 9.0, killtime: 0.95, failed?: false, phases: nil
      )
      expect(result.operators["cmp"]).to eq(count: 2, duration: 0.75)
      expect(result.status_counts["killed"]).to eq(2)
      expect(result.status_counts["survived"]).to eq(1)
    end

    it "counts a mutation listed in two categories once" do
      timed = detail(file: "lib/a.rb", line: 1, operator: "cmp", status: "killed", duration: 0.5)
      result = described_class.from_json(data.merge("timed_out" => [timed]), wall: 1.0)

      expect(result.mutant_count).to eq(3)
    end

    it "keeps the per-mutation status, not the category name" do
      timed = detail(file: "lib/a.rb", line: 9, operator: "cmp", status: "timeout", duration: 30.0)
      result = described_class.from_json({ "timed_out" => [timed] }, wall: 1.0)

      expect(result.statuses.values).to eq(["timeout"])
    end

    it "defaults missing summary timings to zero" do
      result = described_class.from_json({ "killed" => [] }, wall: 1.0)

      expect(result).to have_attributes(duration: 0.0, killtime: 0.0, mutant_count: 0)
    end

    it "is frozen" do
      expect(described_class.from_json(data, wall: 1.0)).to be_frozen
    end
  end

  describe ".failed" do
    it "records the error and has no mutants" do
      result = described_class.failed("exit 1, no JSON", wall: 3.0)

      expect(result).to have_attributes(failed?: true, mutant_count: 0, error: "exit 1, no JSON", wall: 3.0)
    end
  end
end
