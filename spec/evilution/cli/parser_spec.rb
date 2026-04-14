# frozen_string_literal: true

require "stringio"
require "evilution/cli/parser"

RSpec.describe Evilution::CLI::Parser do
  def parse(argv, stdin: StringIO.new)
    described_class.new(argv, stdin: stdin).parse
  end

  describe "top-level command extraction" do
    it "defaults to :run when argv is empty" do
      expect(parse([]).command).to eq(:run)
    end

    it "recognises 'version'" do
      expect(parse(["version"]).command).to eq(:version)
    end

    it "recognises 'init'" do
      expect(parse(["init"]).command).to eq(:init)
    end

    it "recognises 'mcp'" do
      expect(parse(["mcp"]).command).to eq(:mcp)
    end

    it "recognises 'subjects'" do
      expect(parse(["subjects"]).command).to eq(:subjects)
    end

    it "treats an explicit 'run' as :run" do
      expect(parse(["run"]).command).to eq(:run)
    end
  end

  describe "subcommand extraction" do
    it "maps 'session list' to :session_list" do
      expect(parse(%w[session list]).command).to eq(:session_list)
    end

    it "maps 'session show' to :session_show" do
      expect(parse(%w[session show]).command).to eq(:session_show)
    end

    it "maps 'session diff' to :session_diff" do
      expect(parse(%w[session diff]).command).to eq(:session_diff)
    end

    it "maps 'session gc' to :session_gc" do
      expect(parse(%w[session gc]).command).to eq(:session_gc)
    end

    it "maps 'tests list' to :tests_list" do
      expect(parse(%w[tests list]).command).to eq(:tests_list)
    end

    it "maps 'environment show' to :environment_show" do
      expect(parse(%w[environment show]).command).to eq(:environment_show)
    end

    it "maps 'util mutation' to :util_mutation" do
      expect(parse(%w[util mutation]).command).to eq(:util_mutation)
    end

    it "sets parse_error on unknown session subcommand" do
      parsed = parse(%w[session foo])
      expect(parsed.command).to eq(:parse_error)
      expect(parsed.parse_error).to match(/Unknown session subcommand: foo/)
    end

    it "sets parse_error on missing session subcommand" do
      parsed = parse(["session"])
      expect(parsed.command).to eq(:parse_error)
      expect(parsed.parse_error).to match(/Missing session subcommand/)
    end

    it "sets parse_error on unknown tests subcommand" do
      expect(parse(%w[tests foo]).command).to eq(:parse_error)
    end

    it "sets parse_error on missing tests subcommand" do
      expect(parse(["tests"]).command).to eq(:parse_error)
    end

    it "sets parse_error on unknown environment subcommand" do
      expect(parse(%w[environment foo]).command).to eq(:parse_error)
    end

    it "sets parse_error on missing environment subcommand" do
      expect(parse(["environment"]).command).to eq(:parse_error)
    end

    it "sets parse_error on unknown util subcommand" do
      expect(parse(%w[util foo]).command).to eq(:parse_error)
    end

    it "sets parse_error on missing util subcommand" do
      expect(parse(["util"]).command).to eq(:parse_error)
    end
  end

  describe "options" do
    it "parses --jobs" do
      expect(parse(["-j", "4"]).options[:jobs]).to eq(4)
    end

    it "parses --format json" do
      expect(parse(["--format", "json"]).options[:format]).to eq(:json)
    end

    it "parses --fail-fast with numeric argument via preprocess" do
      expect(parse(["--fail-fast", "3"]).options[:fail_fast]).to eq("3")
    end

    it "parses bare --fail-fast as 1" do
      expect(parse(["--fail-fast"]).options[:fail_fast]).to eq(1)
    end

    it "parses --fail-fast=5" do
      expect(parse(["--fail-fast=5"]).options[:fail_fast]).to eq("5")
    end

    it "parses --spec comma list" do
      expect(parse(["--spec", "a_spec.rb,b_spec.rb"]).options[:spec_files]).to eq(%w[a_spec.rb b_spec.rb])
    end

    it "parses --target" do
      expect(parse(["--target", "Foo#bar"]).options[:target]).to eq("Foo#bar")
    end

    it "parses --min-score" do
      expect(parse(["--min-score", "0.85"]).options[:min_score]).to eq(0.85)
    end

    it "parses --timeout" do
      expect(parse(["-t", "10"]).options[:timeout]).to eq(10)
    end

    it "parses --verbose" do
      expect(parse(["-v"]).options[:verbose]).to be(true)
    end

    it "parses --no-baseline" do
      expect(parse(["--no-baseline"]).options[:baseline]).to be(false)
    end

    it "parses --skip-heredoc-literals" do
      expect(parse(["--skip-heredoc-literals"]).options[:skip_heredoc_literals]).to be(true)
    end

    it "parses --related-specs-heuristic" do
      expect(parse(["--related-specs-heuristic"]).options[:related_specs_heuristic]).to be(true)
    end
  end

  describe "file arguments" do
    it "collects positional files" do
      parsed = parse(["lib/a.rb", "lib/b.rb"])
      expect(parsed.files).to eq(%w[lib/a.rb lib/b.rb])
    end

    it "parses a single line" do
      parsed = parse(["lib/a.rb:10"])
      expect(parsed.files).to eq(["lib/a.rb"])
      expect(parsed.line_ranges["lib/a.rb"]).to eq(10..10)
    end

    it "parses a bounded range" do
      parsed = parse(["lib/a.rb:15-30"])
      expect(parsed.line_ranges["lib/a.rb"]).to eq(15..30)
    end

    it "parses an open-ended range" do
      parsed = parse(["lib/a.rb:15-"])
      expect(parsed.line_ranges["lib/a.rb"]).to eq(15..Float::INFINITY)
    end

    it "handles a file arg with no colon (empty line_ranges entry)" do
      parsed = parse(["lib/a.rb"])
      expect(parsed.files).to eq(["lib/a.rb"])
      expect(parsed.line_ranges).to eq({})
    end

    it "combines multiple files with and without ranges" do
      parsed = parse(["lib/a.rb", "lib/b.rb:5-10"])
      expect(parsed.files).to eq(%w[lib/a.rb lib/b.rb])
      expect(parsed.line_ranges).to eq("lib/b.rb" => (5..10))
    end
  end

  describe "stdin files" do
    it "reads file paths from stdin when --stdin is passed" do
      stdin = StringIO.new("lib/a.rb\nlib/b.rb:10-20\n")
      parsed = described_class.new(["--stdin"], stdin: stdin).parse
      expect(parsed.files).to eq(%w[lib/a.rb lib/b.rb])
      expect(parsed.line_ranges["lib/b.rb"]).to eq(10..20)
      expect(parsed.options).not_to have_key(:stdin)
    end

    it "skips empty lines in stdin input" do
      stdin = StringIO.new("lib/a.rb\n\n  \nlib/b.rb\n")
      parsed = described_class.new(["--stdin"], stdin: stdin).parse
      expect(parsed.files).to eq(%w[lib/a.rb lib/b.rb])
    end

    it "sets stdin_error when --stdin is combined with positional files" do
      stdin = StringIO.new("lib/a.rb\n")
      parsed = described_class.new(["--stdin", "lib/x.rb"], stdin: stdin).parse
      expect(parsed.stdin_error).to match(/--stdin cannot be combined/)
    end

    it "only honours --stdin for :run and :subjects commands" do
      stdin = StringIO.new("lib/a.rb\n")
      parsed = described_class.new(["version", "--stdin"], stdin: stdin).parse
      expect(parsed.files).to eq([])
      expect(parsed.options).not_to have_key(:stdin)
    end

    it "honours --stdin for :subjects" do
      stdin = StringIO.new("lib/a.rb\n")
      parsed = described_class.new(["subjects", "--stdin"], stdin: stdin).parse
      expect(parsed.command).to eq(:subjects)
      expect(parsed.files).to eq(["lib/a.rb"])
    end
  end
end
