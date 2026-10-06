# frozen_string_literal: true

$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))
require "calc"

# `double` is covered by a passing example. `triple` is covered only by an
# example that fails whatever the code does, and `half` by nothing.
RSpec.describe Calc do
  it "doubles" do
    expect(described_class.new.double(4)).to eq(8)
  end

  it "triples, according to an example that was never right" do
    expect(described_class.new.triple(2)).to eq(7)
  end
end
