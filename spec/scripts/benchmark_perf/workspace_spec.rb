# frozen_string_literal: true

require "tmpdir"
require_relative "../../../scripts/lib/benchmark_perf/workspace"
require_relative "fake_runner"

RSpec.describe BenchmarkPerf::Workspace do
  around do |example|
    Dir.mktmpdir { |dir| @tmp = dir and example.run }
  end

  let(:runner) { BenchmarkPerfFakeRunner.new }
  let(:target_dir) { File.join(@tmp, "corpus").tap { |d| Dir.mkdir(d) } }
  let(:target) { BenchmarkPerf::Target.new(name: "corpus", dir: target_dir, args: [], env: {}) }
  let(:workspace) { described_class.new(repo_root: "/repo", tmp_root: File.join(@tmp, "trees"), runner: runner) }

  describe "#slug" do
    it "replaces characters unsafe in file names" do
      expect(workspace.slug("feature/x y")).to eq("feature_x_y")
    end
  end

  describe "#tree_for" do
    it "uses the checkout itself for the working tree" do
      expect(workspace.tree_for("worktree")).to eq("/repo")
      expect(runner.calls).to be_empty
    end

    it "exports a ref once and reuses it" do
      2.times { workspace.tree_for("v1.5.0") }

      archives = runner.calls.count { |c| c[:cmd].join(" ").include?("git archive") }
      expect(archives).to eq(1)
      expect(workspace.tree_for("v1.5.0")).to eq(File.join(@tmp, "trees", "v1.5.0"))
    end

    it "rejects an unknown ref" do
      failing = BenchmarkPerfFakeRunner.new { |cmd| cmd.include?("rev-parse") ? ["", "bad ref", false] : ["", "", true] }
      ws = described_class.new(repo_root: "/repo", tmp_root: @tmp, runner: failing)

      expect { ws.tree_for("nope") }.to raise_error(BenchmarkPerf::ConfigError, /unknown ref nope/)
    end
  end

  describe "#label_for" do
    it "names a ref by its short sha" do
      sha_runner = BenchmarkPerfFakeRunner.new { |_cmd| ["abc1234\n", "", true] }
      ws = described_class.new(repo_root: "/repo", tmp_root: @tmp, runner: sha_runner)

      expect(ws.label_for("v1.5.0")).to eq("abc1234")
    end

    it "marks a dirty working tree" do
      dirty = BenchmarkPerfFakeRunner.new { |cmd| cmd.include?("status") ? [" M lib/x.rb\n", "", true] : ["abc1234\n", "", true] }
      ws = described_class.new(repo_root: "/repo", tmp_root: @tmp, runner: dirty)

      expect(ws.label_for("worktree")).to eq("worktree (abc1234, dirty)")
    end
  end

  describe "#prepare" do
    before do
      File.write(File.join(target_dir, "Gemfile"), <<~GEMFILE)
        source "https://rubygems.org"
        gemspec
        gem "evilution", path: "/old/evilution"
        gem "rspec"
      GEMFILE
      File.write(File.join(target_dir, "Gemfile.lock"), "LOCK\n")
    end

    let(:gemfile) { workspace.prepare(target, "worktree") }

    it "writes a Gemfile pointing evilution at the version's tree" do
      content = File.read(gemfile)

      expect(gemfile).to eq(File.join(target_dir, "Gemfile.benchmark_perf.worktree"))
      expect(content).not_to include("/old/evilution")
      expect(content).to include("gemspec", 'gem "rspec"', 'gem "evilution", path: "/repo"')
    end

    it "copies the lockfile next to it" do
      expect(File.read("#{gemfile}.lock")).to eq("LOCK\n")
    end

    it "runs bundle install against the generated Gemfile" do
      gemfile
      install = runner.calls.find { |c| c[:cmd] == %w[bundle install] }

      expect(install).to include(dir: target_dir, env: { "BUNDLE_GEMFILE" => gemfile })
    end

    it "fails on a missing target dir" do
      missing = BenchmarkPerf::Target.new(name: "x", dir: File.join(@tmp, "missing"), args: [], env: {})

      expect { workspace.prepare(missing, "worktree") }.to raise_error(BenchmarkPerf::ConfigError, /missing/)
    end

    it "fails when bundle install fails" do
      failing = BenchmarkPerfFakeRunner.new { |cmd| cmd == %w[bundle install] ? ["", "could not resolve", false] : ["", "", true] }
      ws = described_class.new(repo_root: "/repo", tmp_root: @tmp, runner: failing)

      expect { ws.prepare(target, "worktree") }.to raise_error(BenchmarkPerf::ConfigError, /could not resolve/)
    end
  end
end
