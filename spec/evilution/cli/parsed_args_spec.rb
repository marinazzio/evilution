# frozen_string_literal: true

require "evilution/cli/parsed_args"

RSpec.describe Evilution::CLI::ParsedArgs do
  it "defaults collection fields and error fields" do
    parsed = described_class.new(command: :version)
    expect(parsed.command).to eq(:version)
    expect(parsed.options).to eq({})
    expect(parsed.files).to eq([])
    expect(parsed.line_ranges).to eq({})
    expect(parsed.stdin_error).to be_nil
    expect(parsed.parse_error).to be_nil
  end

  it "accepts populated values" do
    parsed = described_class.new(
      command: :run,
      options: { jobs: 4 },
      files: ["lib/a.rb"],
      line_ranges: { "lib/a.rb" => (1..5) }
    )
    expect(parsed.options).to eq(jobs: 4)
    expect(parsed.files).to eq(["lib/a.rb"])
    expect(parsed.line_ranges).to eq("lib/a.rb" => (1..5))
  end
end
