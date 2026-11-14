# frozen_string_literal: true

require_relative "ledger"

RSpec.configure { |config| config.fail_fast = 1 }

RSpec.describe CovFixtureLedger do
  it "fails first" do
    expect(described_class.new.total).to eq(1)
  end

  it "refunds" do
    ledger = described_class.new
    ledger.refund(5)
    expect(ledger.total).to eq(-5)
  end
end
