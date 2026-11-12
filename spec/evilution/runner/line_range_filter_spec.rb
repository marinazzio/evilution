# frozen_string_literal: true

require "evilution/runner/line_range_filter"

RSpec.describe Evilution::Runner::LineRangeFilter do
  def mutation(file_path, changed_lines)
    instance_double(Evilution::Mutation, file_path: file_path, changed_lines: changed_lines)
  end

  it "keeps every mutation when no line range is given" do
    mutations = [Object.new, Object.new]

    expect(described_class.new({}).call(mutations)).to eq(mutations)
  end

  it "keeps the mutations of a file that has no line range" do
    other = mutation("lib/b.rb", 1..1)

    expect(described_class.new("lib/a.rb" => 10..20).call([other])).to eq([other])
  end

  it "keeps a mutation whose changed lines sit inside the range" do
    inside = mutation("lib/a.rb", 12..14)

    expect(described_class.new("lib/a.rb" => 10..20).call([inside])).to eq([inside])
  end

  it "drops a mutation whose changed lines end before the range" do
    expect(described_class.new("lib/a.rb" => 10..20).call([mutation("lib/a.rb", 2..9)])).to be_empty
  end

  it "drops a mutation whose changed lines start after the range" do
    expect(described_class.new("lib/a.rb" => 10..20).call([mutation("lib/a.rb", 21..21)])).to be_empty
  end

  it "keeps a mutation that starts before the range and reaches into it" do
    reaching = mutation("lib/a.rb", 8..10)

    expect(described_class.new("lib/a.rb" => 10..20).call([reaching])).to eq([reaching])
  end

  it "keeps a mutation that starts inside the range and runs past it" do
    running = mutation("lib/a.rb", 20..25)

    expect(described_class.new("lib/a.rb" => 10..20).call([running])).to eq([running])
  end

  it "keeps a mutation that spans the whole range" do
    spanning = mutation("lib/a.rb", 1..30)

    expect(described_class.new("lib/a.rb" => 10..20).call([spanning])).to eq([spanning])
  end

  it "keeps a mutation past the start of an open-ended range" do
    late = mutation("lib/a.rb", 500..500)

    expect(described_class.new("lib/a.rb" => 10..Float::INFINITY).call([late])).to eq([late])
  end

  it "keeps the order of the mutations it keeps" do
    first = mutation("lib/a.rb", 10..10)
    dropped = mutation("lib/a.rb", 1..1)
    last = mutation("lib/a.rb", 20..20)

    expect(described_class.new("lib/a.rb" => 10..20).call([first, dropped, last])).to eq([first, last])
  end
end
