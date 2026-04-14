# frozen_string_literal: true

require "stringio"
require "evilution/config"
require "evilution/cli/printers/environment"

RSpec.describe Evilution::CLI::Printers::Environment do
  let(:config) do
    instance_double(
      Evilution::Config,
      timeout: 30, format: :text, integration: "rspec", jobs: 1,
      isolation: "auto", baseline: true, incremental: false,
      verbose: false, quiet: false, progress: true,
      fail_fast: nil, min_score: 0.0, suggest_tests: false,
      save_session: false, target: nil,
      skip_heredoc_literals: false, ignore_patterns: []
    )
  end
  let(:io) { StringIO.new }

  it "prints the header with version and ruby info" do
    described_class.new(config, config_file: ".evilution.yml").render(io)
    expect(io.string).to include("Evilution Environment")
    expect(io.string).to include("evilution: #{Evilution::VERSION}")
    expect(io.string).to include("ruby: #{RUBY_VERSION}")
  end

  it "prints the config file path" do
    described_class.new(config, config_file: ".evilution.yml").render(io)
    expect(io.string).to include("config_file: .evilution.yml")
  end

  it "prints (none) when config_file is nil" do
    described_class.new(config, config_file: nil).render(io)
    expect(io.string).to include("config_file: (none)")
  end

  it "prints every setting with its value" do
    described_class.new(config, config_file: nil).render(io)
    expect(io.string).to include("timeout: 30")
    expect(io.string).to include("format: text")
    expect(io.string).to include("integration: rspec")
    expect(io.string).to include("jobs: 1")
    expect(io.string).to include("isolation: auto")
    expect(io.string).to include("baseline: true")
    expect(io.string).to include("incremental: false")
  end

  it "prints (disabled) when fail_fast is nil" do
    described_class.new(config, config_file: nil).render(io)
    expect(io.string).to include("fail_fast: (disabled)")
  end

  it "prints (all files) when target is nil" do
    described_class.new(config, config_file: nil).render(io)
    expect(io.string).to include("target: (all files)")
  end

  it "prints (none) when ignore_patterns is empty" do
    described_class.new(config, config_file: nil).render(io)
    expect(io.string).to include("ignore_patterns: (none)")
  end

  it "prints inspected ignore_patterns when non-empty" do
    allow(config).to receive(:ignore_patterns).and_return(["Foo*"])
    described_class.new(config, config_file: nil).render(io)
    expect(io.string).to include('ignore_patterns: ["Foo*"]')
  end
end
