# frozen_string_literal: true

require_relative "../../../scripts/lib/benchmark_perf/comparison"

RSpec.describe BenchmarkPerf::Comparison do
  def run(wall:, statuses: {}, operators: {})
    BenchmarkPerf::RunResult.new(wall: wall, duration: wall, killtime: 0.0,
                                 statuses: statuses, operators: operators)
  end

  def sample(walls:, statuses: {}, operators: {})
    BenchmarkPerf::VersionSample.new(runs: walls.map { |w| run(wall: w, statuses: statuses, operators: operators) })
  end

  def keys(count, prefix)
    (1..count).to_h { |i| ["#{prefix}#{i}", "killed"] }
  end

  describe "wall decomposition" do
    let(:base) { sample(walls: [200.0], statuses: keys(100, "a")) }
    let(:other) { sample(walls: [450.0], statuses: keys(150, "a")) }
    let(:comparison) { described_class.new(base: base, other: other) }

    it "splits the wall delta into a count effect and a cost effect" do
      expect(comparison.delta_wall).to eq(250.0)
      expect(comparison.count_effect).to eq(100.0)
      expect(comparison.cost_effect).to eq(150.0)
      expect(comparison.count_effect + comparison.cost_effect).to eq(comparison.delta_wall)
    end

    it "has no cost split when the baseline has no mutants" do
      empty = described_class.new(base: sample(walls: [5.0]), other: other)

      expect(empty).to have_attributes(count_effect: nil, cost_effect: nil, delta_wall: 445.0)
    end
  end

  describe "#noise?" do
    let(:base) { sample(walls: [198.0, 200.0, 202.0]) }

    it "is true when the delta is within the combined spread" do
      other = sample(walls: [201.0, 202.0, 203.0])

      expect(described_class.new(base: base, other: other).noise?).to be(true)
    end

    it "is false when the delta exceeds the combined spread" do
      other = sample(walls: [300.0, 301.0, 302.0])

      expect(described_class.new(base: base, other: other).noise?).to be(false)
    end
  end

  describe "verdict changes" do
    let(:base) { sample(walls: [1.0], statuses: { "K1" => "killed", "K2" => "killed", "K3" => "killed" }) }
    let(:other) do
      sample(walls: [1.0], statuses: { "K1" => "survived", "K2" => "timeout", "K3" => "killed", "K4" => "survived" })
    end
    let(:comparison) { described_class.new(base: base, other: other) }

    it "lists kills the other version lost, excluding timeouts" do
      expect(comparison.lost_kills).to eq(["K1"])
    end

    it "lists kills that became timeouts separately" do
      expect(comparison.flips_to_timeout).to eq(["K2"])
    end

    it "counts mutants present in both versions" do
      expect(comparison.common_count).to eq(3)
    end
  end

  describe "#operator_rows" do
    let(:base) do
      sample(walls: [1.0], operators: { "cmp" => { count: 10, duration: 10.0 }, "old" => { count: 2, duration: 1.0 } })
    end
    let(:other) do
      sample(walls: [1.0], operators: { "cmp" => { count: 20, duration: 30.0 }, "new" => { count: 5, duration: 50.0 } })
    end
    let(:rows) { described_class.new(base: base, other: other).operator_rows.to_h { |r| [r.operator, r] } }

    it "splits shared operators into count and cost effects" do
      expect(rows["cmp"]).to have_attributes(state: :both, count_effect: 10.0, cost_effect: 10.0)
    end

    it "marks operators only in the other version as added" do
      expect(rows["new"]).to have_attributes(state: :added, base_count: 0, other_count: 5, count_effect: nil)
    end

    it "marks operators only in the baseline as removed" do
      expect(rows["old"]).to have_attributes(state: :removed, base_count: 2, other_count: 0, cost_effect: nil)
    end

    it "orders rows by absolute duration change" do
      ordered = described_class.new(base: base, other: other).operator_rows.map(&:operator)

      expect(ordered).to eq(%w[new cmp old])
    end
  end

  describe "with a failed sample" do
    let(:failed) { BenchmarkPerf::VersionSample.new(runs: [BenchmarkPerf::RunResult.failed("boom", wall: 1.0)]) }
    let(:comparison) { described_class.new(base: failed, other: sample(walls: [1.0], statuses: { "K" => "survived" })) }

    it "is unavailable and reports nothing" do
      expect(comparison).to have_attributes(available?: false, delta_wall: nil, count_effect: nil,
                                            lost_kills: [], flips_to_timeout: [], operator_rows: [])
    end
  end
end
