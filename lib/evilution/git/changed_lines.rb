# frozen_string_literal: true

require "open3"

require_relative "../git"
require_relative "../line_set"
require_relative "unified_diff"

# The lines changed since a git ref, per file: what a pull request changes.
#
# The diff runs from the merge base of the ref and HEAD -- what `ref...HEAD`
# compares -- so that what the ref gained after the branch left it does not
# count, to the working tree, so that changes not yet committed do. Files git
# does not track yet count whole; those it ignores do not count. Deleted files
# have no lines left to mutate. A rename counts only its edited lines, under
# the new name.
#
# Lines that were only deleted leave no line of their own behind; the lines
# either side of the gap count instead (Evilution::Git::UnifiedDiff), so that
# a method whose only change is a deleted line is still mutated where that
# line was.
#
# Paths are relative to the current directory, as file arguments are, and
# files outside it are left out.
class Evilution::Git::ChangedLines
  # Pinned against the user's git config: Evilution::Git::UnifiedDiff reads
  # the new file's name after a `b/` prefix, colours, external diff tools and
  # text conversion would break that read or shift its lines, and rename
  # detection decides whether a renamed file counts whole.
  DIFF_ARGS = %w[
    diff -U0 --no-color --no-ext-diff --no-textconv --relative --find-renames --diff-filter=ACMRT --dst-prefix=b/
  ].freeze
  private_constant :DIFF_ARGS

  def initialize(ref)
    @ref = ref
  end

  # Returns { path => Evilution::LineSet } for every file with a changed line.
  def call
    ensure_repository
    base = merge_base
    changed = Evilution::Git::UnifiedDiff.parse(git(*DIFF_ARGS, base, "--"))
    untracked.each { |path| changed[path] = Evilution::LineSet.new([1..Float::INFINITY]) }
    changed
  end

  private

  attr_reader :ref

  def ensure_repository
    return if run("rev-parse", "--is-inside-work-tree").last.success?

    raise Evilution::ConfigError, "--since needs a git repository: #{Dir.pwd} is not inside one"
  end

  # A ref starting with a dash reaches rev-parse as an option it rejects, so
  # it is reported unknown before merge-base could read it as one.
  def merge_base
    commit = "#{ref}^{commit}"
    known = run("rev-parse", "--verify", "--quiet", commit).last.success?
    raise Evilution::ConfigError, "--since: unknown git ref '#{ref}'" unless known

    output, status = run("merge-base", commit, "HEAD")
    return output.strip if status.success?

    raise Evilution::ConfigError,
          "--since: no merge base between #{ref} and HEAD. In a shallow clone, fetch the history " \
          "both share (e.g. actions/checkout with fetch-depth: 0, or git fetch --unshallow)"
  end

  def untracked
    git("ls-files", "--others", "--exclude-standard", "-z").split("\0").map { |path| utf8(path) }
  end

  def utf8(text)
    text.dup.force_encoding(Encoding::UTF_8)
  end

  def git(*args)
    output, status = run(*args)
    return output if status.success?

    raise Evilution::ConfigError, "--since: git #{args.first} failed: #{output.strip}"
  end

  # Output is read as bytes: a diff holds whatever the files hold, which need
  # not be valid UTF-8.
  def run(*)
    output, error, status = Open3.capture3("git", "-c", "core.quotePath=false", *, binmode: true)
    [output.empty? ? error : output, status]
  rescue SystemCallError => e
    raise Evilution::ConfigError, "--since needs git, which could not be run: #{e.message}"
  end
end
