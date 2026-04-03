# frozen_string_literal: true

require "evilution/cli"
require_relative "../support/cli_helpers"

RSpec.describe Evilution::CLI, "util mutation command" do
  include CLIHelpers

  let(:summary) do
    instance_double(Evilution::Result::Summary, score: 1.0, success?: true)
  end

  let(:runner) { instance_double(Evilution::Runner, call: summary) }

  before do
    allow(Evilution::Runner).to receive(:new).and_return(runner)
    allow(summary).to receive(:success?).with(min_score: anything).and_return(true)
  end

  describe "with -e flag" do
    it "returns exit code 0" do
      cli = described_class.new(["util", "mutation", "-e", "def foo; x + y; end"])
      capture_stdout { expect(cli.call).to eq(0) }
    end

    it "shows mutations for the given code" do
      cli = described_class.new(["util", "mutation", "-e", "def foo; x + y; end"])
      output = capture_stdout { cli.call }

      expect(output).to include("arithmetic_replacement")
    end

    it "shows mutation diffs" do
      cli = described_class.new(["util", "mutation", "-e", "def foo; x + y; end"])
      output = capture_stdout { cli.call }

      expect(output).to include("- ")
      expect(output).to include("+ ")
    end

    it "shows subject name" do
      cli = described_class.new(["util", "mutation", "-e", "def foo; x + y; end"])
      output = capture_stdout { cli.call }

      expect(output).to include("#foo")
    end

    it "shows total mutation count" do
      cli = described_class.new(["util", "mutation", "-e", "def foo; x + y; end"])
      output = capture_stdout { cli.call }

      expect(output).to match(/\d+ mutation/)
    end

    it "handles methods inside a class" do
      cli = described_class.new(["util", "mutation", "-e", "class Foo; def bar; true; end; end"])
      output = capture_stdout { cli.call }

      expect(output).to include("Foo#bar")
    end

    it "shows message when no mutations generated" do
      cli = described_class.new(["util", "mutation", "-e", "def foo; end"])
      output = capture_stdout { cli.call }

      expect(output).to include("No mutations generated")
    end
  end

  describe "with a file path" do
    let(:tmpfile) do
      f = Tempfile.new(["mutation_preview", ".rb"])
      f.write("def greet(name)\n  \"hello \#{name}\"\nend\n")
      f.flush
      f
    end

    after do
      tmpfile.close
      tmpfile.unlink
    end

    it "returns exit code 0" do
      cli = described_class.new(["util", "mutation", tmpfile.path])
      capture_stdout { expect(cli.call).to eq(0) }
    end

    it "shows mutations for the file" do
      cli = described_class.new(["util", "mutation", tmpfile.path])
      output = capture_stdout { cli.call }

      expect(output).to include("string_literal")
    end
  end

  describe "with --format json" do
    it "outputs JSON" do
      cli = described_class.new(["util", "mutation", "-e", "def foo; x + y; end", "--format", "json"])
      output = capture_stdout { cli.call }
      parsed = JSON.parse(output)

      expect(parsed).to be_an(Array)
      expect(parsed.first).to include("operator", "line", "diff")
    end
  end

  describe "error handling" do
    it "returns exit code 2 when no source given" do
      cli = described_class.new(%w[util mutation])
      output = capture_stderr { expect(cli.call).to eq(2) }

      expect(output).to include("Error:")
    end

    it "returns exit code 2 for nonexistent file" do
      cli = described_class.new(["util", "mutation", "/nonexistent.rb"])
      output = capture_stderr { expect(cli.call).to eq(2) }

      expect(output).to include("Error:")
    end

    it "returns exit code 2 for unparseable code" do
      cli = described_class.new(["util", "mutation", "-e", "def foo("])
      output = capture_stderr { expect(cli.call).to eq(2) }

      expect(output).to include("Error:")
    end
  end

  describe "subcommand routing" do
    it "shows error for unknown util subcommand" do
      cli = described_class.new(%w[util bogus])
      output = capture_stderr { cli.call }

      expect(output).to include("Unknown util subcommand")
    end

    it "shows error for missing util subcommand" do
      cli = described_class.new(%w[util])
      output = capture_stderr { cli.call }

      expect(output).to include("Missing util subcommand")
    end
  end
end
