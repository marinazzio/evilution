# frozen_string_literal: true

require "tmpdir"
require "fileutils"
require "evilution/spec_resolver"

RSpec.describe Evilution::SpecResolver::SiblingSpecRanker do
  subject(:ranker) { described_class.new(test_suffix: "_spec.rb") }

  around do |example|
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) { example.run }
    end
  end

  def create_file(path, content = "")
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, content)
  end

  let(:source) { "app/models/game/round.rb" }
  let(:dirs) { ["spec/models/game"] }

  it "ranks a describe of the subject above a caller above a mention, dropping unrelated specs" do
    create_file("app/models/game/scoring.rb", "class Game::Scoring\n  Round.new\nend\n")
    create_file("spec/models/game/a_spec.rb", "RSpec.describe Game::A do\n  Round\nend\n")
    create_file("spec/models/game/b_spec.rb", "RSpec.describe Game::Round do\nend\n")
    create_file("spec/models/game/scoring_spec.rb", "RSpec.describe Game::Scoring do\nend\n")
    create_file("spec/models/game/z_spec.rb", "RSpec.describe Game::Z do\nend\n")

    expect(ranker.call(source, dirs)).to eq(
      ["spec/models/game/b_spec.rb", "spec/models/game/scoring_spec.rb", "spec/models/game/a_spec.rb"]
    )
  end

  it "orders specs of the same rank by path" do
    create_file("spec/models/game/b_spec.rb", "Round\n")
    create_file("spec/models/game/a_spec.rb", "Round\n")

    expect(ranker.call(source, dirs)).to eq(["spec/models/game/a_spec.rb", "spec/models/game/b_spec.rb"])
  end

  it "merges and de-duplicates specs across several directories" do
    create_file("spec/models/game/a_spec.rb", "Round\n")
    create_file("spec/game/b_spec.rb", "Round\n")

    expect(ranker.call(source, ["spec/models/game", "spec/game", "spec/models/game"]))
      .to eq(["spec/game/b_spec.rb", "spec/models/game/a_spec.rb"])
  end

  it "uses only the first (top-level) describe constant to decide whether a spec names the subject" do
    create_file("app/models/game/scoring.rb", "Round\n")
    create_file("spec/models/game/a_spec.rb", "RSpec.describe Game::Other do\n  describe Game::Round do\n  end\nend\n")
    create_file("spec/models/game/scoring_spec.rb", "RSpec.describe Game::Scoring do\nend\n")

    expect(ranker.call(source, dirs)).to eq(["spec/models/game/scoring_spec.rb", "spec/models/game/a_spec.rb"])
  end

  it "recognises an indented, bare or root-anchored describe" do
    create_file("app/models/game/scoring.rb", "Round\n")
    create_file("spec/models/game/scoring_spec.rb", "")
    create_file("spec/models/game/x_spec.rb", "module Game\n  describe ::Game::Round do\n  end\nend\n")

    expect(ranker.call(source, dirs)).to eq(["spec/models/game/x_spec.rb", "spec/models/game/scoring_spec.rb"])
  end

  it "does not take a describe with a string argument as naming the subject" do
    create_file("app/models/game/scoring.rb", "Round\n")
    create_file("spec/models/game/a_spec.rb", "describe \"Round\" do\n  Round\nend\n")
    create_file("spec/models/game/scoring_spec.rb", "")

    expect(ranker.call(source, dirs)).to eq(["spec/models/game/scoring_spec.rb", "spec/models/game/a_spec.rb"])
  end

  it "ignores a describe of the subject nested under a top-level string describe" do
    create_file("app/models/game/scoring.rb", "Round\n")
    create_file("spec/models/game/a_spec.rb", "RSpec.describe \"stuff\" do\n  describe Game::Round do\n  end\nend\n")
    create_file("spec/models/game/scoring_spec.rb", "")

    expect(ranker.call(source, dirs)).to eq(["spec/models/game/scoring_spec.rb", "spec/models/game/a_spec.rb"])
  end

  it "recognises a parenthesised describe" do
    create_file("app/models/game/scoring.rb", "Round\n")
    create_file("spec/models/game/scoring_spec.rb", "")
    create_file("spec/models/game/x_spec.rb", "RSpec.describe(Game::Round, :slow) do\nend\n")

    expect(ranker.call(source, dirs)).to eq(["spec/models/game/x_spec.rb", "spec/models/game/scoring_spec.rb"])
  end

  it "recognises a describe with a space before its parenthesis" do
    create_file("app/models/game/scoring.rb", "Round\n")
    create_file("spec/models/game/scoring_spec.rb", "")
    create_file("spec/models/game/x_spec.rb", "describe (Game::Round) do\nend\n")

    expect(ranker.call(source, dirs)).to eq(["spec/models/game/x_spec.rb", "spec/models/game/scoring_spec.rb"])
  end

  # Each spec puts a `describe` that is not a call to RSpec's describe ahead of
  # the real one; only the real one may decide the rank.
  it "skips a describe symbol, a describe definition and a describe on another receiver" do
    create_file("app/models/game/scoring.rb", "Round\n")
    create_file("spec/models/game/scoring_spec.rb", "")
    real = "RSpec.describe Game::Round do\nend\n"
    create_file("spec/models/game/a_spec.rb", "let(:describe) { Other }\n#{real}")
    create_file("spec/models/game/b_spec.rb", "def describe(x) = x\n#{real}")
    create_file("spec/models/game/c_spec.rb", "helper.describe Other\n#{real}")
    create_file("spec/models/game/d_spec.rb", "helper&.describe Other\n#{real}")

    expect(ranker.call(source, dirs)).to eq(
      %w[a b c d].map { |name| "spec/models/game/#{name}_spec.rb" } + ["spec/models/game/scoring_spec.rb"]
    )
  end

  it "takes a leading describe without a receiver as the top-level describe" do
    create_file("app/models/game/scoring.rb", "Round\n")
    create_file("spec/models/game/scoring_spec.rb", "")
    create_file("spec/models/game/x_spec.rb", "describe Other do\n  describe Game::Round do\n  end\nend\n")

    expect(ranker.call(source, dirs)).to eq(["spec/models/game/scoring_spec.rb", "spec/models/game/x_spec.rb"])
  end

  it "does not count the subject name in a comment, a string, a heredoc or an embedded document" do
    create_file("spec/models/game/a_spec.rb", "# Round\n\"Round\"\n'Round'\n:Round\n<<~TXT\n  Round\nTXT\n=begin\nRound\n=end\n")

    expect(ranker.call(source, dirs)).to eq([])
  end

  it "counts the subject constant inside string interpolation" do
    create_file("spec/models/game/a_spec.rb", "\"#\{Round.name}\"\n")

    expect(ranker.call(source, dirs)).to eq(["spec/models/game/a_spec.rb"])
  end

  it "does not count a caller whose mirrored source names the subject only in a comment or string" do
    create_file("app/models/game/scoring.rb", "# Round\nclass Game::Scoring\n  NAME = \"Round\"\nend\n")
    create_file("spec/models/game/scoring_spec.rb", "RSpec.describe Game::Scoring do\nend\n")

    expect(ranker.call(source, dirs)).to eq([])
  end

  it "skips, without reading, the specs that spec_pattern excludes" do
    create_file("spec/models/game/a_spec.rb", "Round\n")
    create_file("spec/models/game/b_spec.rb", "Round\n")
    files = class_spy(Evilution::SpecResolver::ProjectFiles)
    allow(files).to receive(:glob) { |pattern| Dir.glob(pattern) }
    allow(files).to receive(:read) { |path| File.exist?(path) ? File.binread(path) : "" }
    ranker = described_class.new(test_suffix: "_spec.rb", files: files)

    expect(ranker.call(source, dirs, spec_pattern: "**/b_spec.rb")).to eq(["spec/models/game/b_spec.rb"])
    expect(files).not_to have_received(:read).with("spec/models/game/a_spec.rb")
  end

  it "ranks a spec named after the subject first even when it does not mention the constant" do
    create_file("spec/models/game/z_spec.rb", "RSpec.describe Game::Round do\nend\n")
    create_file("spec/models/game/round_spec.rb", "")

    expect(ranker.call(source, dirs)).to eq(["spec/models/game/round_spec.rb", "spec/models/game/z_spec.rb"])
  end

  it "does not count a caller whose mirrored source is missing" do
    create_file("spec/models/game/scoring_spec.rb", "RSpec.describe Game::Scoring do\nend\n")

    expect(ranker.call(source, dirs)).to eq([])
  end

  it "matches whole constant segments only" do
    create_file("spec/models/game/a_spec.rb", "RoundHelper; NewRound; Round_x; round\n")
    create_file("spec/models/game/b_spec.rb", "Game::Round::LIMIT\n")

    expect(ranker.call(source, dirs)).to eq(["spec/models/game/b_spec.rb"])
  end

  it "does not scan subdirectories of the given directories" do
    create_file("spec/models/game/deeper/a_spec.rb", "Round\n")

    expect(ranker.call(source, dirs)).to eq([])
  end

  it "ignores files without the test suffix" do
    create_file("spec/models/game/helper.rb", "Round\n")
    create_file("spec/models/game/test_round.rb", "Round\n")

    expect(ranker.call(source, dirs)).to eq([])
  end

  it "tolerates files that are not valid UTF-8" do
    create_file("spec/models/game/a_spec.rb", "\xFF\xFE Round\n".b)

    expect(ranker.call(source, dirs)).to eq(["spec/models/game/a_spec.rb"])
  end

  it "returns nothing for no directories" do
    expect(ranker.call(source, [])).to eq([])
  end

  context "with the minitest suffix" do
    subject(:ranker) { described_class.new(test_suffix: "_test.rb") }

    let(:dirs) { ["test/models/game"] }

    it "also scans test_-prefixed files and maps them to their mirrored source" do
      create_file("app/models/game/scoring.rb", "Round.new\n")
      create_file("test/models/game/test_scoring.rb", "class TestScoring < Minitest::Test; end\n")
      create_file("test/models/game/a_test.rb", "Game::Round\n")

      expect(ranker.call(source, dirs)).to eq(["test/models/game/test_scoring.rb", "test/models/game/a_test.rb"])
    end

    it "ranks a test_-prefixed file named after the subject first" do
      create_file("test/models/game/a_test.rb", "Game::Round\n")
      create_file("test/models/game/test_round.rb", "")

      expect(ranker.call(source, dirs)).to eq(["test/models/game/test_round.rb", "test/models/game/a_test.rb"])
    end
  end
end
