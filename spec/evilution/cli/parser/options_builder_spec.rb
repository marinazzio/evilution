# frozen_string_literal: true

require "tmpdir"
require "evilution/cli/parser/options_builder"

RSpec.describe Evilution::CLI::Parser::OptionsBuilder do
  def parse(argv)
    options = {}
    remaining = described_class.build(options).parse!(argv)
    [options, remaining]
  end

  it "returns an OptionParser instance" do
    expect(described_class.build({})).to be_a(OptionParser)
  end

  it "parses --jobs into options hash" do
    options, = parse(["-j", "4"])
    expect(options[:jobs]).to eq(4)
  end

  it "parses --format as a symbol" do
    options, = parse(["--format", "json"])
    expect(options[:format]).to eq(:json)
  end

  it "parses --spec as an array" do
    options, = parse(["--spec", "a_spec.rb,b_spec.rb"])
    expect(options[:spec_files]).to eq(%w[a_spec.rb b_spec.rb])
  end

  it "parses --min-score as a float" do
    options, = parse(["--min-score", "0.85"])
    expect(options[:min_score]).to eq(0.85)
  end

  it "parses --target as a string" do
    options, = parse(["--target", "Foo#bar"])
    expect(options[:target]).to eq("Foo#bar")
  end

  it "parses --no-baseline to false" do
    options, = parse(["--no-baseline"])
    expect(options[:baseline]).to be(false)
  end

  it "parses --verbose" do
    options, = parse(["-v"])
    expect(options[:verbose]).to be(true)
  end

  it "parses --fallback-full-suite" do
    options, = parse(["--fallback-full-suite"])
    expect(options[:fallback_to_full_suite]).to be(true)
  end

  it "parses --skip-heredoc-literals" do
    options, = parse(["--skip-heredoc-literals"])
    expect(options[:skip_heredoc_literals]).to be(true)
  end

  it "parses --results-dir" do
    options, = parse(["--results-dir", "/tmp/results"])
    expect(options[:results_dir]).to eq("/tmp/results")
  end

  it "parses --limit as integer" do
    options, = parse(["--limit", "5"])
    expect(options[:limit]).to eq(5)
  end

  it "leaves positional arguments untouched" do
    _options, remaining = parse(["-v", "lib/a.rb", "lib/b.rb"])
    expect(remaining).to eq(%w[lib/a.rb lib/b.rb])
  end

  it "parses --spec-pattern as a string glob" do
    options, = parse(["--spec-pattern", "spec/requests/**/*_spec.rb"])
    expect(options[:spec_pattern]).to eq("spec/requests/**/*_spec.rb")
  end

  it "expands --spec-dir into spec_files via FileArgs" do
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "a_spec.rb"), "")
      options, = parse(["--spec-dir", dir])
      expect(options[:spec_files]).to eq([File.join(dir, "a_spec.rb")])
    end
  end

  it "parses --no-example-targeting to false" do
    options, = parse(["--no-example-targeting"])
    expect(options[:example_targeting]).to be(false)
  end

  it "parses --example-targeting-fallback as a string" do
    options, = parse(["--example-targeting-fallback", "unresolved"])
    expect(options[:example_targeting_fallback]).to eq("unresolved")
  end
end
