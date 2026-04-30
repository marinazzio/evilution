# frozen_string_literal: true

require "evilution/mutation"

RSpec.describe Evilution::Mutation::Location do
  it "exposes file_path, line, column" do
    loc = described_class.new(file_path: "lib/x.rb", line: 5, column: 7)

    expect(loc.file_path).to eq("lib/x.rb")
    expect(loc.line).to eq(5)
    expect(loc.column).to eq(7)
  end
end
