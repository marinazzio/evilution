# frozen_string_literal: true

require "stringio"
require "evilution/cli/commands/version"
require "evilution/cli/parsed_args"

RSpec.describe Evilution::CLI::Commands::Version do
  it "prints the gem version and returns exit code 0 in the result" do
    parsed = Evilution::CLI::ParsedArgs.new(command: :version)
    out = StringIO.new
    result = described_class.new(parsed, stdout: out).call
    expect(out.string.strip).to eq(Evilution::VERSION)
    expect(result.exit_code).to eq(0)
    expect(result.error).to be_nil
  end

  it "is registered with the dispatcher under :version" do
    require "evilution/cli/dispatcher"
    expect(Evilution::CLI::Dispatcher.registered?(:version)).to be(true)
    expect(Evilution::CLI::Dispatcher.lookup(:version)).to eq(described_class)
  end
end
