# frozen_string_literal: true

require "fileutils"
require "shellwords"
require_relative "manifest"

# Turns a version (git ref or "worktree") into an evilution tree on disk and
# wires that tree into a corpus repo through a generated Gemfile.
class BenchmarkPerf::Workspace
  WORKTREE = "worktree"
  EVILUTION_LINE = /^\s*gem\s+["']evilution["'].*\n?/

  def initialize(repo_root:, tmp_root:, runner:)
    @repo_root = repo_root
    @tmp_root = tmp_root
    @runner = runner
    @trees = {}
  end

  def slug(ref)
    BenchmarkPerf.slug(ref)
  end

  def tree_for(ref)
    return @repo_root if ref == WORKTREE

    @trees[ref] ||= export(ref)
  end

  def label_for(ref)
    return short_sha(ref) unless ref == WORKTREE

    "worktree (#{short_sha("HEAD")}, #{tree_state})"
  end

  def prepare(target, ref)
    raise BenchmarkPerf::ConfigError, "target dir missing: #{target.dir}" unless Dir.exist?(target.dir)

    gemfile = File.join(target.dir, "Gemfile.benchmark_perf.#{slug(ref)}")
    write_gemfile(target.dir, gemfile, tree_for(ref))
    _, stderr, ok = @runner.call(%w[bundle install], dir: target.dir, env: { "BUNDLE_GEMFILE" => gemfile })
    raise BenchmarkPerf::ConfigError, "bundle install failed in #{target.dir} for #{ref}: #{stderr}" unless ok

    gemfile
  end

  private

  def export(ref)
    _, _, ok = git("rev-parse", "--verify", "--quiet", "#{ref}^{commit}")
    raise BenchmarkPerf::ConfigError, "unknown ref #{ref}" unless ok

    dir = File.join(@tmp_root, slug(ref))
    FileUtils.mkdir_p(dir)
    pipeline = "git archive #{Shellwords.escape(ref)} | tar -x -C #{Shellwords.escape(dir)}"
    _, stderr, ok = @runner.call(["sh", "-c", pipeline], dir: @repo_root)
    raise BenchmarkPerf::ConfigError, "git archive #{ref} failed: #{stderr}" unless ok

    dir
  end

  def write_gemfile(dir, gemfile, tree)
    original = File.read(File.join(dir, "Gemfile")).gsub(EVILUTION_LINE, "")
    File.write(gemfile, "#{original.chomp}\ngem \"evilution\", path: #{tree.inspect}\n")
    lock = File.join(dir, "Gemfile.lock")
    FileUtils.cp(lock, "#{gemfile}.lock") if File.exist?(lock)
  end

  def tree_state
    stdout, = git("status", "--porcelain")
    stdout.strip.empty? ? "clean" : "dirty"
  end

  def short_sha(ref)
    stdout, = git("rev-parse", "--short", ref)
    stdout.strip
  end

  def git(*args)
    @runner.call(["git", *args], dir: @repo_root)
  end
end
