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

  it "treats a describe with a string argument as a mention, not as naming the subject" do
    create_file("app/models/game/scoring.rb", "Round\n")
    create_file("spec/models/game/a_spec.rb", "describe \"Round\" do\nend\n")
    create_file("spec/models/game/scoring_spec.rb", "")

    expect(ranker.call(source, dirs)).to eq(["spec/models/game/scoring_spec.rb", "spec/models/game/a_spec.rb"])
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
