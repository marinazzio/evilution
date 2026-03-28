# frozen_string_literal: true

require "English"

require_relative "../git"

class Evilution::Git::ChangedFiles
  MAIN_BRANCHES = %w[main master origin/main origin/master].freeze
  SOURCE_PREFIXES = %w[lib/ app/].freeze

  def call
    main_branch = detect_main_branch
    merge_base = run_git("merge-base", "HEAD", main_branch)
    diff_output = run_git("diff", "--name-only", "--diff-filter=ACMR", "#{merge_base}..HEAD")

    files = diff_output.split("\n").select { |f| ruby_source_file?(f) }
    raise Evilution::Error, "no changed Ruby files found since merge base with #{main_branch}" if files.empty?

    files
  end

  private

  def detect_main_branch
    MAIN_BRANCHES.each do |branch|
      return branch if branch_exists?(branch)
    end

    raise Evilution::Error, "could not detect main branch (tried #{MAIN_BRANCHES.join(", ")})"
  end

  def branch_exists?(name)
    run_git("rev-parse", "--verify", name)
    true
  rescue Evilution::Error => e
    raise if e.message.include?("not a git repository")

    false
  end

  def ruby_source_file?(path)
    path.end_with?(".rb") && SOURCE_PREFIXES.any? { |prefix| path.start_with?(prefix) }
  end

  def run_git(*args)
    output = `git #{args.join(" ")} 2>&1`.strip
    raise Evilution::Error, "not a git repository" if output.include?("not a git repository")
    raise Evilution::Error, "git command failed: git #{args.join(" ")}: #{output}" unless $CHILD_STATUS.success?

    output
  end
end
