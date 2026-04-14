# frozen_string_literal: true

require "evilution/reporter/html/sections/header"

RSpec.describe Evilution::Reporter::HTML::Sections::Header do
  def summary(score:)
    double("Summary", score: score)
  end

  it "renders the score as percentage" do
    html = described_class.new(summary(score: 0.1234)).render
    expect(html).to include("12.34%")
  end

  it "uses score-high class when score >= 0.8" do
    html = described_class.new(summary(score: 0.85)).render
    expect(html).to include("score-badge score-high")
  end

  it "uses score-medium class when 0.5 <= score < 0.8" do
    html = described_class.new(summary(score: 0.6)).render
    expect(html).to include("score-badge score-medium")
  end

  it "uses score-low class when score < 0.5" do
    html = described_class.new(summary(score: 0.1)).render
    expect(html).to include("score-badge score-low")
  end

  it "includes the Evilution version tag" do
    html = described_class.new(summary(score: 0.5)).render
    expect(html).to include("<span class=\"version\">v#{Evilution::VERSION}</span>")
  end
end
