# frozen_string_literal: true

require "evilution/reporter/html/sections/baseline_comparison"

RSpec.describe Evilution::Reporter::HTML::Sections::BaselineComparison do
  def summary(score:)
    double("Summary", score: score)
  end

  it "returns empty string when baseline is nil" do
    expect(described_class.render_if(nil, summary(score: 0.5))).to eq("")
  end

  it "renders both scores and the delta" do
    baseline = { "summary" => { "score" => 0.6 } }
    html = described_class.render_if(baseline, summary(score: 0.8))
    expect(html).to include("Baseline: 60.00%")
    expect(html).to include("Current: 80.00%")
    expect(html).to include("+20.00%")
  end

  it "uses delta-positive class when score improved" do
    baseline = { "summary" => { "score" => 0.5 } }
    html = described_class.render_if(baseline, summary(score: 0.7))
    expect(html).to include("delta-positive")
  end

  it "uses delta-negative class when score dropped" do
    baseline = { "summary" => { "score" => 0.8 } }
    html = described_class.render_if(baseline, summary(score: 0.6))
    expect(html).to include("delta-negative")
  end

  it "uses delta-neutral class when scores are equal" do
    baseline = { "summary" => { "score" => 0.75 } }
    html = described_class.render_if(baseline, summary(score: 0.75))
    expect(html).to include("delta-neutral")
  end

  it "defaults missing baseline summary to zero" do
    html = described_class.render_if({}, summary(score: 0.5))
    expect(html).to include("Baseline: 0.00%")
  end
end
