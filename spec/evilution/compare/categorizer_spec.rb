# frozen_string_literal: true

require "evilution/compare/categorizer"

RSpec.describe Evilution::Compare::Categorizer do
  def record(fp:, status:, file: "lib/x.rb", line: 1, source: :evilution, operator: nil)
    Evilution::Compare::Record.new(
      source: source, file_path: file, line: line, status: status,
      fingerprint: fp, operator: operator, diff_body: "", raw: {}
    )
  end

  describe ".call" do
    it "buckets identical alive fingerprints into shared_alive with both records" do
      against = [record(fp: "fp1", status: :survived)]
      current = [record(fp: "fp1", status: :survived, line: 2)]

      result = described_class.call(against, current)

      expect(result[:shared_alive].size).to eq(1)
      expect(result[:shared_alive].first[:against]).to eq(against.first)
      expect(result[:shared_alive].first[:current]).to eq(current.first)
      expect(result[:alive_only_against]).to be_empty
      expect(result[:alive_only_current]).to be_empty
      expect(result[:shared_dead]).to be_empty
    end

    it "collapses all dead statuses into shared_dead" do
      against = [record(fp: "fp1", status: :killed)]
      current = [record(fp: "fp1", status: :timeout)]

      result = described_class.call(against, current)

      expect(result[:shared_dead].size).to eq(1)
      expect(result[:shared_dead].first[:against]).to eq(against.first)
      expect(result[:shared_dead].first[:current]).to eq(current.first)
    end

    it "treats :error as dead for shared_dead bucketing" do
      against = [record(fp: "fp1", status: :error)]
      current = [record(fp: "fp1", status: :killed)]

      result = described_class.call(against, current)

      expect(result[:shared_dead].size).to eq(1)
    end

    it "reports regressions (dead->alive) in alive_only_current with peer_status" do
      against = [record(fp: "fp1", status: :killed)]
      current = [record(fp: "fp1", status: :survived)]

      result = described_class.call(against, current)

      expect(result[:alive_only_current].size).to eq(1)
      entry = result[:alive_only_current].first
      expect(entry[:record]).to eq(current.first)
      expect(entry[:peer_status]).to eq(:killed)
      expect(result[:alive_only_against]).to be_empty
    end

    it "reports fixes (alive->dead) in alive_only_against with peer_status" do
      against = [record(fp: "fp1", status: :survived)]
      current = [record(fp: "fp1", status: :killed)]

      result = described_class.call(against, current)

      expect(result[:alive_only_against].size).to eq(1)
      entry = result[:alive_only_against].first
      expect(entry[:record]).to eq(against.first)
      expect(entry[:peer_status]).to eq(:killed)
      expect(result[:alive_only_current]).to be_empty
    end

    it "records absent peer with nil peer_status when alive fingerprint only in against" do
      against = [record(fp: "fp1", status: :survived)]
      current = []

      result = described_class.call(against, current)

      expect(result[:alive_only_against].size).to eq(1)
      expect(result[:alive_only_against].first[:peer_status]).to be_nil
    end

    it "records absent peer with nil peer_status when alive fingerprint only in current" do
      against = []
      current = [record(fp: "fp1", status: :survived)]

      result = described_class.call(against, current)

      expect(result[:alive_only_current].size).to eq(1)
      expect(result[:alive_only_current].first[:peer_status]).to be_nil
    end

    it "does not bucket a dead-only fingerprint and does not increment excluded counts" do
      against = [record(fp: "fp1", status: :killed)]
      current = []

      result = described_class.call(against, current)

      expect(result[:alive_only_against]).to be_empty
      expect(result[:alive_only_current]).to be_empty
      expect(result[:shared_alive]).to be_empty
      expect(result[:shared_dead]).to be_empty
      expect(result[:excluded_against]).to eq(0)
      expect(result[:excluded_current]).to eq(0)
    end

    it "counts excluded status and pushes live peer into alive_only bucket with excluded peer_status" do
      against = [record(fp: "fp1", status: :neutral)]
      current = [record(fp: "fp1", status: :survived)]

      result = described_class.call(against, current)

      expect(result[:excluded_against]).to eq(1)
      expect(result[:excluded_current]).to eq(0)
      expect(result[:alive_only_current].size).to eq(1)
      expect(result[:alive_only_current].first[:peer_status]).to eq(:neutral)
    end

    it "counts both excluded sides and emits no bucket entries when both excluded" do
      against = [record(fp: "fp1", status: :equivalent)]
      current = [record(fp: "fp1", status: :unresolved)]

      result = described_class.call(against, current)

      expect(result[:excluded_against]).to eq(1)
      expect(result[:excluded_current]).to eq(1)
      expect(result[:alive_only_against]).to be_empty
      expect(result[:alive_only_current]).to be_empty
      expect(result[:shared_alive]).to be_empty
      expect(result[:shared_dead]).to be_empty
    end

    it "sorts each bucket by [file_path, line, fingerprint] for determinism" do
      against = [
        record(fp: "fp_c", status: :survived, file: "lib/c.rb", line: 1),
        record(fp: "fp_a", status: :survived, file: "lib/a.rb", line: 5),
        record(fp: "fp_b", status: :survived, file: "lib/a.rb", line: 2)
      ]
      current = []

      result = described_class.call(against, current)

      ordered = result[:alive_only_against].map { |e| e[:record].fingerprint }
      expect(ordered).to eq(%w[fp_b fp_a fp_c])
    end

    it "sorts shared buckets by against record key" do
      against = [
        record(fp: "fp_z", status: :survived, file: "lib/z.rb", line: 9),
        record(fp: "fp_a", status: :survived, file: "lib/a.rb", line: 1)
      ]
      current = [
        record(fp: "fp_a", status: :survived, file: "lib/a.rb", line: 1),
        record(fp: "fp_z", status: :survived, file: "lib/z.rb", line: 9)
      ]

      result = described_class.call(against, current)

      ordered = result[:shared_alive].map { |e| e[:against].fingerprint }
      expect(ordered).to eq(%w[fp_a fp_z])
    end

    it "returns empty buckets and zero counts for empty inputs" do
      result = described_class.call([], [])

      expect(result[:alive_only_against]).to eq([])
      expect(result[:alive_only_current]).to eq([])
      expect(result[:shared_alive]).to eq([])
      expect(result[:shared_dead]).to eq([])
      expect(result[:excluded_against]).to eq(0)
      expect(result[:excluded_current]).to eq(0)
    end

    it "returns exactly the six documented keys" do
      result = described_class.call([], [])

      expect(result.keys).to contain_exactly(
        :alive_only_against,
        :alive_only_current,
        :shared_alive,
        :shared_dead,
        :excluded_against,
        :excluded_current
      )
    end
  end
end
