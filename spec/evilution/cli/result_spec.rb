# frozen_string_literal: true

require "evilution/cli/result"

RSpec.describe Evilution::CLI::Result do
  it "defaults error to nil and error_rendered to false" do
    result = described_class.new(exit_code: 0)
    expect(result.exit_code).to eq(0)
    expect(result.error).to be_nil
    expect(result.error_rendered).to be(false)
  end

  it "carries an error and rendered flag" do
    err = Evilution::Error.new("boom")
    result = described_class.new(exit_code: 2, error: err, error_rendered: true)
    expect(result.exit_code).to eq(2)
    expect(result.error).to eq(err)
    expect(result.error_rendered).to be(true)
  end
end
