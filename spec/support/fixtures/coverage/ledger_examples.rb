# frozen_string_literal: true

require_relative "ledger"

RSpec.describe CovFixtureLedger do
  it "adds" do
    ledger = described_class.new
    ledger.add(5)
    expect(ledger.total).to eq(5)
  end
end
