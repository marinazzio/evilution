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

  it "parses --incremental to true" do
    options, = parse(["--incremental"])
    expect(options[:incremental]).to be(true)
  end

  it "parses --no-incremental to false" do
    options, = parse(["--no-incremental"])
    expect(options[:incremental]).to be(false)
  end

  it "applies last-wins when --incremental and --no-incremental are both given" do
    options, = parse(["--incremental", "--no-incremental"])
    expect(options[:incremental]).to be(false)

    options, = parse(["--no-incremental", "--incremental"])
    expect(options[:incremental]).to be(true)
  end

  it "parses --canary to true" do
    options, = parse(["--canary"])
    expect(options[:canary]).to be(true)
  end

  it "parses --no-canary to false" do
    options, = parse(["--no-canary"])
    expect(options[:canary]).to be(false)
  end

  it "parses --quiet-children to true" do
    options, = parse(["--quiet-children"])
    expect(options[:quiet_children]).to be(true)
  end

  it "parses --quiet-children-dir as a string" do
    options, = parse(["--quiet-children-dir", "log/evilution_workers"])
    expect(options[:quiet_children_dir]).to eq("log/evilution_workers")
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

  it "captures --against path" do
    options, = parse(["--against=prior.json"])
    expect(options[:against]).to eq("prior.json")
  end

  it "captures --current path" do
    options, = parse(["--current=curr.json"])
    expect(options[:current]).to eq("curr.json")
  end

  it "parses --profile as a string" do
    options, = parse(["--profile", "strict"])
    expect(options[:profile]).to eq("strict")
  end

  it "parses --strict as shortcut for --profile=strict" do
    options, = parse(["--strict"])
    expect(options[:profile]).to eq("strict")
  end

  it "sets the OptionParser banner" do
    expect(described_class.build({}).help).to start_with("Usage: evilution [command] [options] [files...]")
  end

  it "sets the OptionParser version" do
    expect(described_class.build({}).version).to eq(Evilution::VERSION)
  end

  it "includes the line-range targeting separator in help text" do
    expect(described_class.build({}).help).to include("Line-range targeting: lib/foo.rb:15-30")
  end

  it "includes the commands separator in help text" do
    help = described_class.build({}).help
    expect(help).to include("Commands: run (default; alias: mutate), init, session {list,show,diff,gc}, subjects,")
    expect(help).to include("tests {list}, util {mutation}, environment {show}, compare, mcp, version")
  end

  it "includes the Options separator in help text" do
    expect(described_class.build({}).help).to include("Options:")
  end

  it "places a blank separator line between the banner and the line-range section" do
    lines = described_class.build({}).help.split("\n", -1)
    range_index = lines.index("Line-range targeting: lib/foo.rb:15-30, lib/foo.rb:15, lib/foo.rb:15-")
    expect(lines[range_index - 1]).to eq("")
  end

  it "places a blank separator line between the line-range section and the commands section" do
    lines = described_class.build({}).help.split("\n", -1)
    commands_index = lines.index(
      "Commands: run (default; alias: mutate), init, session {list,show,diff,gc}, subjects,"
    )
    expect(lines[commands_index - 1]).to eq("")
  end

  it "places a blank separator line between the commands section and the Options heading" do
    lines = described_class.build({}).help.split("\n", -1)
    options_index = lines.index("Options:")
    expect(lines[options_index - 1]).to eq("")
  end

  it "emits the header sections separated by exactly the expected blank lines" do
    lines = described_class.build({}).help.split("\n", -1)
    expect(lines[0..7]).to eq(
      [
        "Usage: evilution [command] [options] [files...]",
        "",
        "Line-range targeting: lib/foo.rb:15-30, lib/foo.rb:15, lib/foo.rb:15-",
        "",
        "Commands: run (default; alias: mutate), init, session {list,show,diff,gc}, subjects,",
        "         tests {list}, util {mutation}, environment {show}, compare, mcp, version",
        "",
        "Options:"
      ]
    )
  end

  it "parses --timeout as an integer" do
    options, = parse(["--timeout", "30"])
    expect(options[:timeout]).to eq(30)
  end

  it "omits :timeout when --timeout is absent" do
    options, = parse([])
    expect(options).not_to have_key(:timeout)
  end

  it "parses --fail-fast to 1" do
    options, = parse(["--fail-fast"])
    expect(options[:fail_fast]).to eq(1)
  end

  it "omits :fail_fast when --fail-fast is absent" do
    options, = parse([])
    expect(options).not_to have_key(:fail_fast)
  end

  it "parses --stdin to true" do
    options, = parse(["--stdin"])
    expect(options[:stdin]).to be(true)
  end

  it "omits :stdin when --stdin is absent" do
    options, = parse([])
    expect(options).not_to have_key(:stdin)
  end

  it "parses --integration as a string" do
    options, = parse(["--integration", "minitest"])
    expect(options[:integration]).to eq("minitest")
  end

  it "omits :integration when --integration is absent" do
    options, = parse([])
    expect(options).not_to have_key(:integration)
  end

  it "parses --isolation as a string" do
    options, = parse(["--isolation", "fork"])
    expect(options[:isolation]).to eq("fork")
  end

  it "omits :isolation when --isolation is absent" do
    options, = parse([])
    expect(options).not_to have_key(:isolation)
  end

  it "parses --preload as a string" do
    options, = parse(["--preload", "spec/spec_helper.rb"])
    expect(options[:preload]).to eq("spec/spec_helper.rb")
  end

  it "parses --no-preload to false" do
    options, = parse(["--no-preload"])
    expect(options[:preload]).to be(false)
  end

  it "omits :preload when neither --preload nor --no-preload is given" do
    options, = parse([])
    expect(options).not_to have_key(:preload)
  end

  it "parses --suggest-tests to true" do
    options, = parse(["--suggest-tests"])
    expect(options[:suggest_tests]).to be(true)
  end

  it "omits :suggest_tests when --suggest-tests is absent" do
    options, = parse([])
    expect(options).not_to have_key(:suggest_tests)
  end

  it "parses --no-progress to false" do
    options, = parse(["--no-progress"])
    expect(options[:progress]).to be(false)
  end

  it "omits :progress when --no-progress is absent" do
    options, = parse([])
    expect(options).not_to have_key(:progress)
  end

  it "parses --related-specs-heuristic to true" do
    options, = parse(["--related-specs-heuristic"])
    expect(options[:related_specs_heuristic]).to be(true)
  end

  it "omits :related_specs_heuristic when --related-specs-heuristic is absent" do
    options, = parse([])
    expect(options).not_to have_key(:related_specs_heuristic)
  end

  it "parses --show-disabled to true" do
    options, = parse(["--show-disabled"])
    expect(options[:show_disabled]).to be(true)
  end

  it "omits :show_disabled when --show-disabled is absent" do
    options, = parse([])
    expect(options).not_to have_key(:show_disabled)
  end

  it "parses --baseline-session as a string" do
    options, = parse(["--baseline-session", "prior_session"])
    expect(options[:baseline_session]).to eq("prior_session")
  end

  it "omits :baseline_session when --baseline-session is absent" do
    options, = parse([])
    expect(options).not_to have_key(:baseline_session)
  end

  it "parses --save-session to true" do
    options, = parse(["--save-session"])
    expect(options[:save_session]).to be(true)
  end

  it "omits :save_session when --save-session is absent" do
    options, = parse([])
    expect(options).not_to have_key(:save_session)
  end

  it "parses --eval as a string" do
    options, = parse(["--eval", "1 + 1"])
    expect(options[:eval]).to eq("1 + 1")
  end

  it "omits :eval when --eval is absent" do
    options, = parse([])
    expect(options).not_to have_key(:eval)
  end

  it "parses --quiet to true" do
    options, = parse(["--quiet"])
    expect(options[:quiet]).to be(true)
  end

  it "omits :quiet when --quiet is absent" do
    options, = parse([])
    expect(options).not_to have_key(:quiet)
  end

  it "parses --since as a string" do
    options, = parse(["--since", "2026-01-01"])
    expect(options[:since]).to eq("2026-01-01")
  end

  it "omits :since when --since is absent" do
    options, = parse([])
    expect(options).not_to have_key(:since)
  end

  it "parses --older-than as a string" do
    options, = parse(["--older-than", "30d"])
    expect(options[:older_than]).to eq("30d")
  end

  it "omits :older_than when --older-than is absent" do
    options, = parse([])
    expect(options).not_to have_key(:older_than)
  end
end
