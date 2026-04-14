# frozen_string_literal: true

require "evilution/reporter/html/sections/truncation_notice"

RSpec.describe Evilution::Reporter::HTML::Sections::TruncationNotice do
  it "returns empty string when not truncated" do
    summary = double("Summary", truncated?: false)
    expect(described_class.render_if(summary)).to eq("")
  end

  it "renders the notice when truncated" do
    summary = double("Summary", truncated?: true)
    html = described_class.render_if(summary)
    expect(html).to include("truncation-notice")
    expect(html).to include("Truncated")
  end
end
