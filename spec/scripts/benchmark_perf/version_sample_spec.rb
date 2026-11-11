# frozen_string_literal: true

require_relative "../../../scripts/lib/benchmark_perf/version_sample"

RSpec.describe BenchmarkPerf::VersionSample do
  def run(wall:, statuses: {}, operators: {}, killtime: 0.0)
    BenchmarkPerf::RunResult.new(wall: wall, duration: wall, killtime: killtime,
                                 statuses: statuses, operators: operators)
  end

  def failed(wall: 1.0)
    BenchmarkPerf::RunResult.failed("exit 1: boom", wall: wall)
  end

  it "reports median, min and max wall time" do
    sample = described_class.new(runs: [run(wall: 10.0), run(wall: 14.0), run(wall: 12.0)])

    expect(sample).to have_attributes(wall_median: 12.0, wall_min: 10.0, wall_max: 14.0)
  end

  it "uses the mean of the two middle values for an even count" do
    sample = described_class.new(runs: [run(wall: 10.0), run(wall: 14.0)])

    expect(sample.wall_median).to eq(12.0)
  end

  describe "#statuses" do
    def sample_with(*statuses)
      described_class.new(runs: statuses.map { |s| run(wall: 1.0, statuses: { "K" => s }) })
    end

    it "takes the most frequent status" do
      sample = sample_with("killed", "survived", "killed")

      expect(sample.statuses).to eq("K" => "killed")
      expect(sample.unstable_count).to eq(1)
    end

    it "breaks a tie involving killed towards the non-killed status" do
      expect(sample_with("killed", "survived").statuses).to eq("K" => "survived")
    end

    it "breaks other ties by status order" do
      expect(sample_with("timeout", "survived").statuses).to eq("K" => "survived")
    end

    it "counts no unstable mutants when every run agrees" do
      expect(sample_with("killed", "killed").unstable_count).to eq(0)
    end

    it "derives mutant count and status counts from majority statuses" do
      runs = [run(wall: 1.0, statuses: { "A" => "killed", "B" => "survived" })] * 2
      sample = described_class.new(runs: runs)

      expect(sample.mutant_count).to eq(2)
      expect(sample.status_counts).to eq("killed" => 1, "survived" => 1)
    end
  end

  it "computes medians over successful runs only" do
    sample = described_class.new(runs: [run(wall: 10.0), failed(wall: 99.0), run(wall: 20.0)])

    expect(sample).to have_attributes(failed_count: 1, wall_median: 15.0, failed?: false)
    expect(sample.errors).to eq(["exit 1: boom"])
  end

  it "is failed when no run succeeded" do
    sample = described_class.new(runs: [failed, failed])

    expect(sample).to have_attributes(failed?: true, wall_median: nil, killtime_median: nil, mutant_count: 0)
  end

  it "takes operator counts from the first run and the median duration" do
    runs = [1.0, 3.0, 2.0].map { |d| run(wall: 1.0, operators: { "cmp" => { count: 4, duration: d } }) }

    expect(described_class.new(runs: runs).operators).to eq("cmp" => { count: 4, duration: 2.0 })
  end

  it "reports median killtime and duration" do
    sample = described_class.new(runs: [run(wall: 4.0, killtime: 1.0), run(wall: 6.0, killtime: 3.0)])

    expect(sample).to have_attributes(killtime_median: 2.0, duration_median: 5.0)
  end
end
