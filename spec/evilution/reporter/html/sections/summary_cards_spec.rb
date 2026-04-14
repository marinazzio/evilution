# frozen_string_literal: true

require "evilution/reporter/html/sections/summary_cards"

RSpec.describe Evilution::Reporter::HTML::Sections::SummaryCards do
  def summary(overrides = {})
    defaults = {
      total: 10, killed: 5, survived: 3, timed_out: 1, errors: 0,
      neutral: 0, equivalent: 1, unresolved: 0, skipped: 0,
      duration: 2.5, efficiency: 0.82, mutations_per_second: 4.0,
      peak_memory_mb: nil
    }
    double("Summary", defaults.merge(overrides))
  end

  it "renders core totals" do
    html = described_class.new(summary).render
    expect(html).to include(">10</span><span class=\"card-label\">Total</span>")
    expect(html).to include(">5</span><span class=\"card-label\">Killed</span>")
    expect(html).to include(">3</span><span class=\"card-label\">Survived</span>")
  end

  it "omits unresolved card when zero" do
    expect(described_class.new(summary).render).not_to include("Unresolved")
  end

  it "includes unresolved card when positive" do
    html = described_class.new(summary(unresolved: 2)).render
    expect(html).to include(">2</span><span class=\"card-label\">Unresolved</span>")
  end

  it "omits skipped card when zero" do
    expect(described_class.new(summary).render).not_to include("Skipped")
  end

  it "omits efficiency and rate when duration is zero" do
    html = described_class.new(summary(duration: 0)).render
    expect(html).not_to include("Efficiency")
    expect(html).not_to include("Rate")
  end

  it "renders efficiency and rate when duration is positive" do
    html = described_class.new(summary).render
    expect(html).to include("82.0%")
    expect(html).to include("4.00/s")
  end

  it "omits peak memory card when nil" do
    expect(described_class.new(summary).render).not_to include("Peak Memory")
  end

  it "renders peak memory when present" do
    html = described_class.new(summary(peak_memory_mb: 256.7)).render
    expect(html).to include("256.7 MB")
    expect(html).to include("Peak Memory")
  end
end
