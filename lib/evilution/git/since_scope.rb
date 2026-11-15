# frozen_string_literal: true

require_relative "../git"
require_relative "../line_set"
require_relative "changed_files"
require_relative "changed_lines"

# Limits the files and line ranges of a run to the lines changed since a git
# ref (--since REF), handing back the same files and ranges a command line
# would give, for the rest of the run to treat as it treats those.
#
# Without file arguments, every changed Ruby file under lib/ or app/ is taken,
# as the run without arguments takes the git-changed files. With them, the
# files are only narrowed: a file given that did not change drops out, and a
# file's line range keeps only its changed lines. Every file kept has a line
# set, so a file never runs whole by having none.
class Evilution::Git::SinceScope
  Paths = Data.define(:files, :ranges)

  # ref: the git ref, or nil for no --since, which leaves files and
  # line_ranges as given.
  #
  # A file given must exist and be a file: one that did not change drops out
  # of the run, so a misspelled path or a directory would otherwise pass
  # without anything checked.
  def self.apply(ref, files:, line_ranges:)
    return Paths.new(files: files, ranges: line_ranges) if ref.nil?

    files.each { |file| check_file(file) }
    new(Evilution::Git::ChangedLines.new(ref).call).call(files: files, line_ranges: line_ranges)
  end

  def self.check_file(file)
    return if File.file?(file)
    raise Evilution::ConfigError, "file not found: #{file}" unless File.exist?(file)

    raise Evilution::ConfigError,
          "#{file} is a directory; --since takes files, or no file arguments for every changed file under lib/ and app/"
  end
  private_class_method :check_file

  # changed: { path => Evilution::LineSet }, as Evilution::Git::ChangedLines
  # returns it.
  def initialize(changed)
    @changed = changed
  end

  def call(files:, line_ranges:)
    files.empty? ? changed_sources : given_files(files, line_ranges)
  end

  private

  attr_reader :changed

  def changed_sources
    picked = changed.select { |path, _| source_file?(path) }.sort.to_h
    Paths.new(files: picked.keys, ranges: picked)
  end

  def source_file?(path)
    path.end_with?(".rb") && Evilution::Git::ChangedFiles::SOURCE_PREFIXES.any? { |prefix| path.start_with?(prefix) }
  end

  def given_files(files, line_ranges)
    by_full_path = changed.transform_keys { |path| File.expand_path(path) }
    ranges = {}
    files.each do |file|
      lines = by_full_path[File.expand_path(file)]
      next if lines.nil?

      lines &= line_ranges[file] if line_ranges.key?(file)
      ranges[file] = lines unless lines.empty?
    end
    Paths.new(files: ranges.keys, ranges: ranges)
  end
end
