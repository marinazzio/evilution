# frozen_string_literal: true

require "evilution/cli/parser/command_extractor"

RSpec.describe Evilution::CLI::Parser::CommandExtractor do
  def extract(argv)
    described_class.call(argv)
  end

  describe "top-level commands" do
    it "defaults to :run when argv is empty" do
      result = extract([])
      expect(result.command).to eq(:run)
      expect(result.remaining_argv).to eq([])
      expect(result.parse_error).to be_nil
    end

    it "maps 'version'" do
      expect(extract(["version"]).command).to eq(:version)
    end

    it "maps 'init'" do
      expect(extract(["init"]).command).to eq(:init)
    end

    it "maps 'mcp'" do
      expect(extract(["mcp"]).command).to eq(:mcp)
    end

    it "maps 'subjects'" do
      expect(extract(["subjects"]).command).to eq(:subjects)
    end

    it "treats explicit 'run' as :run" do
      expect(extract(["run"]).command).to eq(:run)
    end

    it "shifts the simple command off remaining_argv" do
      expect(extract(["version", "--flag"]).remaining_argv).to eq(["--flag"])
    end

    it "does not shift when no command keyword is present" do
      expect(extract(["lib/foo.rb"]).remaining_argv).to eq(["lib/foo.rb"])
    end
  end

  describe "session subcommands" do
    it "maps 'session list'" do
      expect(extract(%w[session list]).command).to eq(:session_list)
    end

    it "maps 'session show'" do
      expect(extract(%w[session show]).command).to eq(:session_show)
    end

    it "maps 'session diff'" do
      expect(extract(%w[session diff]).command).to eq(:session_diff)
    end

    it "maps 'session gc'" do
      expect(extract(%w[session gc]).command).to eq(:session_gc)
    end

    it "sets parse_error on unknown session subcommand" do
      result = extract(%w[session foo])
      expect(result.command).to eq(:parse_error)
      expect(result.parse_error).to match(/Unknown session subcommand: foo/)
    end

    it "sets parse_error on missing session subcommand" do
      result = extract(["session"])
      expect(result.command).to eq(:parse_error)
      expect(result.parse_error).to match(/Missing session subcommand/)
    end
  end

  describe "tests subcommands" do
    it "maps 'tests list'" do
      expect(extract(%w[tests list]).command).to eq(:tests_list)
    end

    it "parse_errors on unknown tests subcommand" do
      expect(extract(%w[tests foo]).command).to eq(:parse_error)
    end

    it "parse_errors on missing tests subcommand" do
      expect(extract(["tests"]).command).to eq(:parse_error)
    end
  end

  describe "environment subcommands" do
    it "maps 'environment show'" do
      expect(extract(%w[environment show]).command).to eq(:environment_show)
    end

    it "parse_errors on unknown environment subcommand" do
      expect(extract(%w[environment foo]).command).to eq(:parse_error)
    end

    it "parse_errors on missing environment subcommand" do
      expect(extract(["environment"]).command).to eq(:parse_error)
    end
  end

  describe "util subcommands" do
    it "maps 'util mutation'" do
      expect(extract(%w[util mutation]).command).to eq(:util_mutation)
    end

    it "parse_errors on unknown util subcommand" do
      expect(extract(%w[util foo]).command).to eq(:parse_error)
    end

    it "parse_errors on missing util subcommand" do
      expect(extract(["util"]).command).to eq(:parse_error)
    end
  end

  describe "argv isolation" do
    it "does not mutate the caller's argv array" do
      argv = %w[session list --flag]
      extract(argv)
      expect(argv).to eq(%w[session list --flag])
    end
  end
end
