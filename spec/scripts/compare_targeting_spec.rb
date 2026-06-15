# frozen_string_literal: true

require "json"

load File.expand_path("../../scripts/compare_targeting", __dir__)

RSpec.describe CompareTargeting do
  # A mutation detail as evilution's JSON reporter emits it.
  def detail(file:, line:, operator:, status:, duration:, diff: "- x\n+ y\n")
    { "file" => file, "line" => line, "operator" => operator,
      "status" => status, "duration" => duration, "diff" => diff }
  end

  # An evilution JSON report: per-status category arrays.
  def report(*details)
    grouped = Hash.new { |h, k| h[k] = [] }
    details.each { |d| grouped[d["status"]] << d }
    {
      "killed" => grouped["killed"], "survived" => grouped["survived"],
      "unresolved" => grouped["unresolved"], "errors" => grouped["errors"]
    }
  end

  describe CompareTargeting::ModeResult do
    it "keys mutations by file:line:operator:diff with status and duration" do
      data = report(
        detail(file: "lib/a.rb", line: 3, operator: "cmp", status: "killed", duration: 0.5),
        detail(file: "lib/a.rb", line: 7, operator: "lit", status: "survived", duration: 0.2)
      )
      result = described_class.from_json(data)

      expect(result.killed_count).to eq(1)
      expect(result.measurable_count).to eq(2) # killed + survived
      expect(result.total_duration).to be_within(1e-9).of(0.7)
    end

    it "does not double-count a mutation that appears in overlapping categories" do
      d = detail(file: "lib/a.rb", line: 3, operator: "cmp", status: "killed", duration: 0.5)
      data = { "killed" => [d], "timed_out" => [], "errors" => [] }
      expect(described_class.from_json(data).killed_count).to eq(1)
    end
  end

  describe CompareTargeting::Comparison do
    def mode(*details)
      CompareTargeting::ModeResult.from_json(report(*details))
    end

    let(:m1) { detail(file: "lib/a.rb", line: 3, operator: "cmp", status: "killed", duration: 1.0) }
    let(:m2) { detail(file: "lib/a.rb", line: 7, operator: "lit", status: "killed", duration: 1.0) }

    it "computes per-mode score = killed / measurable" do
      comparison = described_class.new(
        full_file: mode(m1, m2),
        lexical: mode(m1, m2),
        coverage: mode(m1, m2)
      )
      expect(comparison.score("coverage")).to eq(1.0)
    end

    it "counts lost kills: mutations full-file killed but coverage did not kill" do
      # coverage marks m2 survived (a LOST KILL) while full-file killed it.
      m2_survived = detail(file: "lib/a.rb", line: 7, operator: "lit", status: "survived", duration: 0.1)
      comparison = described_class.new(
        full_file: mode(m1, m2),
        lexical: mode(m1, m2),
        coverage: mode(m1, m2_survived)
      )
      expect(comparison.lost_kills("coverage")).to eq(["lib/a.rb:7:lit"])
      expect(comparison.to_row("acme/foo")[:lost_kills]).to eq(1)
    end

    it "computes a wall-time ratio relative to the full-file baseline" do
      fast = detail(file: "lib/a.rb", line: 3, operator: "cmp", status: "killed", duration: 0.25)
      comparison = described_class.new(
        full_file: mode(m1),       # 1.0s
        lexical: mode(m1),
        coverage: mode(fast)       # 0.25s
      )
      expect(comparison.wall_ratio("coverage")).to be_within(1e-9).of(0.25)
    end
  end

  describe CompareTargeting::TableReporter do
    it "renders a markdown table and a PASS/FAIL gate line on total lost kills" do
      rows = [
        { repo: "acme/foo", score_full: 0.8, score_lexical: 0.7, score_coverage: 0.8,
          lost_kills: 0, wall_ratio_lexical: 0.5, wall_ratio_coverage: 0.4 }
      ]
      md = described_class.new(rows).to_markdown

      expect(md).to include("| acme/foo |")
      expect(md).to include("lost_kills")
      expect(md).to match(/GATE.*PASS/)
    end

    it "fails the gate when any repo has lost kills" do
      rows = [{ repo: "acme/foo", score_full: 0.8, score_lexical: 0.7, score_coverage: 0.7,
                lost_kills: 2, wall_ratio_lexical: 0.5, wall_ratio_coverage: 0.4 }]
      expect(described_class.new(rows).to_markdown).to match(/GATE.*FAIL/)
    end
  end

  describe CompareTargeting::ModeRunner do
    it "invokes evilution with the mode's --example-targeting flag and parses the JSON" do
      captured = nil
      runner = described_class.new(command_runner: lambda { |cmd, _dir|
        captured = cmd
        JSON.generate({ "killed" => [detail(file: "lib/a.rb", line: 3, operator: "cmp",
                                            status: "killed", duration: 0.5)] })
      })

      result = runner.run(repo_dir: "/repos/foo", evilution_args: ["lib/a.rb"], mode: "coverage")

      expect(captured).to include("--example-targeting", "coverage", "--format", "json")
      expect(result.killed_count).to eq(1)
    end
  end
end
