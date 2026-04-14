# frozen_string_literal: true

require "tmpdir"
require "stringio"
require "evilution/cli/commands/init"
require "evilution/cli/parsed_args"
require "evilution/config"

RSpec.describe Evilution::CLI::Commands::Init do
  around do |example|
    Dir.mktmpdir { |dir| Dir.chdir(dir) { example.run } }
  end

  let(:parsed) { Evilution::CLI::ParsedArgs.new(command: :init) }
  let(:out) { StringIO.new }
  let(:err) { StringIO.new }

  it "writes .evilution.yml with the default template and exits 0" do
    result = described_class.new(parsed, stdout: out, stderr: err).call
    expect(result.exit_code).to eq(0)
    expect(File.read(".evilution.yml")).to eq(Evilution::Config.default_template)
    expect(out.string).to include("Created .evilution.yml")
  end

  it "warns and exits 1 when the file already exists" do
    File.write(".evilution.yml", "# existing")
    result = described_class.new(parsed, stdout: out, stderr: err).call
    expect(result.exit_code).to eq(1)
    expect(err.string).to include(".evilution.yml already exists")
  end

  it "is registered with the dispatcher under :init" do
    require "evilution/cli/dispatcher"
    expect(Evilution::CLI::Dispatcher.registered?(:init)).to be(true)
    expect(Evilution::CLI::Dispatcher.lookup(:init)).to eq(described_class)
  end
end
