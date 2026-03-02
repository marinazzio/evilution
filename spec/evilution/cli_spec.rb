# frozen_string_literal: true

require "stringio"
require "evilution/cli"

RSpec.describe Evilution::CLI do
  let(:summary) do
    instance_double(Evilution::Result::Summary, score: 1.0, success?: true)
  end

  let(:runner) { instance_double(Evilution::Runner, call: summary) }

  before do
    allow(Evilution::Runner).to receive(:new).and_return(runner)
    allow(summary).to receive(:success?).with(min_score: anything).and_return(true)
  end

  def capture_stdout
    io = StringIO.new
    original = $stdout
    $stdout = io
    yield
    io.string
  ensure
    $stdout = original
  end

  describe "version command" do
    it "outputs the gem version" do
      cli = described_class.new(["version"])
      output = capture_stdout { cli.call }
      expect(output).to include(Evilution::VERSION)
    end

    it "returns exit code 0" do
      cli = described_class.new(["version"])
      capture_stdout { expect(cli.call).to eq(0) }
    end
  end

  describe "run command" do
    describe "--format flag" do
      it "sets format to :json when --format json is given" do
        cli = described_class.new(["--format", "json"])
        cli.call
        expect(Evilution::Runner).to have_received(:new).with(
          config: have_attributes(format: :json)
        )
      end

      it "sets format to :text when --format text is given" do
        cli = described_class.new(["--format", "text"])
        cli.call
        expect(Evilution::Runner).to have_received(:new).with(
          config: have_attributes(format: :text)
        )
      end
    end

    describe "--jobs flag" do
      it "sets jobs to the given integer" do
        cli = described_class.new(["--jobs", "4"])
        cli.call
        expect(Evilution::Runner).to have_received(:new).with(
          config: have_attributes(jobs: 4)
        )
      end

      it "also accepts the short form -j" do
        cli = described_class.new(["-j", "8"])
        cli.call
        expect(Evilution::Runner).to have_received(:new).with(
          config: have_attributes(jobs: 8)
        )
      end
    end

    describe "--timeout flag" do
      it "sets timeout to the given integer" do
        cli = described_class.new(["--timeout", "30"])
        cli.call
        expect(Evilution::Runner).to have_received(:new).with(
          config: have_attributes(timeout: 30)
        )
      end

      it "also accepts the short form -t" do
        cli = described_class.new(["-t", "5"])
        cli.call
        expect(Evilution::Runner).to have_received(:new).with(
          config: have_attributes(timeout: 5)
        )
      end
    end

    describe "--quiet flag" do
      it "sets quiet to true" do
        cli = described_class.new(["--quiet"])
        cli.call
        expect(Evilution::Runner).to have_received(:new).with(
          config: have_attributes(quiet: true)
        )
      end

      it "also accepts the short form -q" do
        cli = described_class.new(["-q"])
        cli.call
        expect(Evilution::Runner).to have_received(:new).with(
          config: have_attributes(quiet: true)
        )
      end
    end

    describe "exit code" do
      it "returns 0 when the mutation score meets min_score" do
        allow(summary).to receive(:success?).with(min_score: 0.0).and_return(true)
        cli = described_class.new([])
        expect(cli.call).to eq(0)
      end

      it "returns 1 when the mutation score does not meet min_score" do
        allow(summary).to receive(:success?).with(min_score: 0.9).and_return(false)
        cli = described_class.new(["--min-score", "0.9"])
        expect(cli.call).to eq(1)
      end
    end

    describe "positional file arguments" do
      it "passes remaining args as target_files" do
        cli = described_class.new(["lib/foo.rb", "lib/bar.rb"])
        cli.call
        expect(Evilution::Runner).to have_received(:new).with(
          config: have_attributes(target_files: ["lib/foo.rb", "lib/bar.rb"])
        )
      end

      it "accepts the explicit run subcommand before files" do
        cli = described_class.new(["run", "lib/foo.rb"])
        cli.call
        expect(Evilution::Runner).to have_received(:new).with(
          config: have_attributes(target_files: ["lib/foo.rb"])
        )
      end
    end
  end
end
