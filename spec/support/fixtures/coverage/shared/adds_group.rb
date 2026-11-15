# frozen_string_literal: true

RSpec.shared_examples "cov fixture adds" do
  it "adds" do
    expect(described_class.new.add(2, 3)).to eq(5)
  end
end
