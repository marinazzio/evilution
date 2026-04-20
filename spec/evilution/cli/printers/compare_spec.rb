# frozen_string_literal: true

require "stringio"
require "json"
require "evilution/compare/record"
require "evilution/cli/printers/compare"

RSpec.describe Evilution::CLI::Printers::Compare do
  def record(fp:, file: "lib/x.rb", line: 1, operator: "Op::Swap", status: :survived)
    Evilution::Compare::Record.new(
      source: :evilution, file_path: file, line: line, status: status,
      fingerprint: fp, operator: operator, diff_body: "", raw: {}
    )
  end

  def empty_buckets
    {
      alive_only_against: [],
      alive_only_current: [],
      shared_alive: [],
      shared_dead: [],
      excluded_against: 0,
      excluded_current: 0
    }
  end

  let(:io) { StringIO.new }

  describe "JSON format" do
    let(:buckets) do
      {
        alive_only_against: [
          { record: record(fp: "abc1234aaaa", file: "lib/foo.rb", line: 42, operator: "Arith::Swap"),
            peer_status: :killed }
        ],
        alive_only_current: [
          { record: record(fp: "def5678bbbb", file: "lib/bar.rb", line: 7, operator: "BooleanLit::Flip"),
            peer_status: nil },
          { record: record(fp: "0123456cccc", file: "lib/baz.rb", line: 10, operator: nil),
            peer_status: :killed },
          { record: record(fp: "eeeeeeedddd", file: "lib/zzz.rb", line: 99, operator: "Literal::Swap"),
            peer_status: :timeout }
        ],
        shared_alive: [
          { against: record(fp: "789abcdeeee", file: "lib/qux.rb", line: 3, operator: "Cond::Flip"),
            current: record(fp: "789abcdeeee", file: "lib/qux.rb", line: 3, operator: "Cond::Flip") }
        ],
        shared_dead: [],
        excluded_against: 0,
        excluded_current: 0
      }
    end

    it "outputs top-level keys in the documented order" do
      described_class.new(buckets, format: :json).render(io)
      keys = JSON.parse(io.string).keys
      expect(keys).to eq(%w[schema summary alive_only_against alive_only_current shared_alive shared_dead])
    end

    it "embeds the SCHEMA constant verbatim" do
      described_class.new(buckets, format: :json).render(io)
      expect(JSON.parse(io.string)["schema"]).to eq(described_class::SCHEMA)
    end

    it "summary has all seven keys including delta" do
      described_class.new(buckets, format: :json).render(io)
      summary = JSON.parse(io.string)["summary"]
      expect(summary.keys).to contain_exactly(
        "alive_only_against", "alive_only_current", "shared_alive", "shared_dead",
        "excluded_against", "excluded_current", "delta"
      )
    end

    it "computes delta as current - against" do
      described_class.new(buckets, format: :json).render(io)
      # current=3, against=1 => delta=2
      expect(JSON.parse(io.string)["summary"]["delta"]).to eq(2)
    end

    it "serializes alive-only entries with five positional elements" do
      described_class.new(buckets, format: :json).render(io)
      entry = JSON.parse(io.string)["alive_only_against"].first
      expect(entry).to eq(["lib/foo.rb", 42, "Arith::Swap", "abc1234aaaa", "killed"])
    end

    it "renders peer_status=nil as 'absent'" do
      described_class.new(buckets, format: :json).render(io)
      entry = JSON.parse(io.string)["alive_only_current"].first
      expect(entry.last).to eq("absent")
    end

    it "serializes shared entries with four positional elements" do
      described_class.new(buckets, format: :json).render(io)
      entry = JSON.parse(io.string)["shared_alive"].first
      expect(entry).to eq(["lib/qux.rb", 3, "Cond::Flip", "789abcdeeee"])
    end

    it "renders nil operator as JSON null" do
      described_class.new(buckets, format: :json).render(io)
      entry = JSON.parse(io.string)["alive_only_current"][1]
      expect(entry[2]).to be_nil
      expect(io.string).to include("null")
    end

    it "emits single-line output" do
      described_class.new(buckets, format: :json).render(io)
      # puts adds one trailing newline; body itself has no internal newline.
      expect(io.string.count("\n")).to eq(1)
    end

    it "handles empty input with structure intact" do
      described_class.new(empty_buckets, format: :json).render(io)
      parsed = JSON.parse(io.string)
      expect(parsed["alive_only_against"]).to eq([])
      expect(parsed["alive_only_current"]).to eq([])
      expect(parsed["shared_alive"]).to eq([])
      expect(parsed["shared_dead"]).to eq([])
      expect(parsed["summary"]["delta"]).to eq(0)
    end
  end

  describe "text format" do
    let(:buckets) do
      {
        alive_only_against: [
          { record: record(fp: "abc1234aaaa", file: "lib/foo.rb", line: 42, operator: "Arith::Swap"),
            peer_status: :killed }
        ],
        alive_only_current: [
          { record: record(fp: "def5678bbbb", file: "lib/bar.rb", line: 7, operator: "BooleanLit::Flip"),
            peer_status: nil },
          { record: record(fp: "0123456cccc", file: "lib/baz.rb", line: 10, operator: nil),
            peer_status: :killed }
        ],
        shared_alive: [
          { against: record(fp: "789abcdeeee", file: "lib/qux.rb", line: 3, operator: "Cond::Flip"),
            current: record(fp: "789abcdeeee", file: "lib/qux.rb", line: 3, operator: "Cond::Flip") }
        ],
        shared_dead: [
          { against: record(fp: "111aaaaxxxx", file: "lib/a.rb", line: 1, operator: "Op::X"),
            current: record(fp: "111aaaaxxxx", file: "lib/a.rb", line: 1, operator: "Op::X") }
        ],
        excluded_against: 0,
        excluded_current: 1
      }
    end

    it "prints the Compare results header with a dashed rule" do
      described_class.new(buckets, format: :text).render(io)
      expect(io.string).to include("Compare results")
      expect(io.string).to include("-" * 3)
    end

    it "summary line contains all counts and delta" do
      described_class.new(buckets, format: :text).render(io)
      out = io.string
      expect(out).to include("alive_only_against=1")
      expect(out).to include("alive_only_current=2")
      expect(out).to include("shared_alive=1")
      expect(out).to include("shared_dead=1")
      expect(out).to include("excluded=0/1")
      expect(out).to include("delta=+1")
    end

    it "prefixes negative delta with minus" do
      b = empty_buckets.merge(
        alive_only_against: [
          { record: record(fp: "aaa0001"), peer_status: nil },
          { record: record(fp: "aaa0002"), peer_status: nil }
        ]
      )
      described_class.new(b, format: :text).render(io)
      expect(io.string).to include("delta=-2")
    end

    it "renders zero delta as '±0'" do
      b = empty_buckets.merge(excluded_current: 1)
      described_class.new(b, format: :text).render(io)
      expect(io.string).to include("delta=\u00B10")
    end

    it "prints 'excluded=A/C' in summary" do
      described_class.new(buckets, format: :text).render(io)
      expect(io.string).to include("excluded=0/1")
    end

    it "includes bucket header with count" do
      described_class.new(buckets, format: :text).render(io)
      expect(io.string).to include("alive_only_current (2):")
    end

    it "omits bucket header when count is zero" do
      b = empty_buckets.merge(
        alive_only_current: [{ record: record(fp: "ccc0001"), peer_status: nil }]
      )
      described_class.new(b, format: :text).render(io)
      out = io.string
      expect(out).not_to include("alive_only_against (")
      expect(out).not_to include("shared_alive (")
      expect(out).not_to include("shared_dead (")
    end

    it "appends '(current: <status>)' to alive_only_against rows" do
      described_class.new(buckets, format: :text).render(io)
      expect(io.string).to include("(current: killed)")
    end

    it "appends '(against: absent)' when peer_status is nil" do
      described_class.new(buckets, format: :text).render(io)
      expect(io.string).to include("(against: absent)")
    end

    it "shared rows have no trailing peer marker" do
      b = empty_buckets.merge(
        shared_alive: [
          { against: record(fp: "sh00001", file: "lib/s.rb", line: 2, operator: "Op::S"),
            current: record(fp: "sh00001", file: "lib/s.rb", line: 2, operator: "Op::S") }
        ]
      )
      described_class.new(b, format: :text).render(io)
      out = io.string
      expect(out).not_to include("(current:")
      expect(out).not_to include("(against:")
    end

    it "renders nil operator as literal '(mutant)'" do
      described_class.new(buckets, format: :text).render(io)
      expect(io.string).to include("(mutant)")
    end

    it "truncates fingerprint to seven chars" do
      described_class.new(buckets, format: :text).render(io)
      expect(io.string).to include("abc1234")
      expect(io.string).not_to include("abc1234aaaa")
    end

    it "prints 'No mutations to compare.' for fully empty input" do
      described_class.new(empty_buckets, format: :text).render(io)
      expect(io.string).to include("No mutations to compare.")
    end
  end

  describe "unknown format" do
    it "raises Evilution::Error" do
      expect { described_class.new(empty_buckets, format: :html).render(io) }
        .to raise_error(Evilution::Error, /unknown compare format/)
    end
  end
end
