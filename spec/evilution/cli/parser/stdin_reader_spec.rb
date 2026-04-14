# frozen_string_literal: true

require "stringio"
require "evilution/cli/parser/stdin_reader"

RSpec.describe Evilution::CLI::Parser::StdinReader do
  def read(io, existing_files: [])
    described_class.call(io, existing_files: existing_files)
  end

  it "reads file paths one per line" do
    result = read(StringIO.new("lib/a.rb\nlib/b.rb:10-20\n"))
    expect(result.files).to eq(%w[lib/a.rb lib/b.rb])
    expect(result.ranges["lib/b.rb"]).to eq(10..20)
    expect(result.error).to be_nil
  end

  it "skips empty and whitespace-only lines" do
    result = read(StringIO.new("lib/a.rb\n\n  \nlib/b.rb\n"))
    expect(result.files).to eq(%w[lib/a.rb lib/b.rb])
  end

  it "returns an error when existing_files is non-empty" do
    result = read(StringIO.new("lib/a.rb\n"), existing_files: ["lib/x.rb"])
    expect(result.error).to match(/--stdin cannot be combined/)
    expect(result.files).to eq([])
    expect(result.ranges).to eq({})
  end
end
