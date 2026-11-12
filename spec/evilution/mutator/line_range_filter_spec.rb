# frozen_string_literal: true

require "evilution/mutator/line_range_filter"

RSpec.describe Evilution::Mutator::LineRangeFilter do
  let(:filter) { described_class.new("lib/a.rb" => 10..20) }

  it "covers every change when no line range is given" do
    expect(described_class.new({}).cover?("lib/a.rb", 1..1)).to be(true)
  end

  it "covers the changes of a file that has no line range" do
    expect(filter.cover?("lib/b.rb", 1..1)).to be(true)
  end

  it "covers changed lines that sit inside the range" do
    expect(filter.cover?("lib/a.rb", 12..14)).to be(true)
  end

  it "does not cover changed lines that end before the range" do
    expect(filter.cover?("lib/a.rb", 2..9)).to be(false)
  end

  it "does not cover changed lines that start after the range" do
    expect(filter.cover?("lib/a.rb", 21..21)).to be(false)
  end

  it "covers changed lines that start before the range and reach into it" do
    expect(filter.cover?("lib/a.rb", 8..10)).to be(true)
  end

  it "covers changed lines that start inside the range and run past it" do
    expect(filter.cover?("lib/a.rb", 20..25)).to be(true)
  end

  it "covers changed lines that span the whole range" do
    expect(filter.cover?("lib/a.rb", 1..30)).to be(true)
  end

  it "covers changed lines past the start of an open-ended range" do
    expect(described_class.new("lib/a.rb" => 10..Float::INFINITY).cover?("lib/a.rb", 500..500)).to be(true)
  end
end
