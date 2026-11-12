# frozen_string_literal: true

require_relative "../spec_resolver"
require_relative "project_files"

# Ranks the test files that sit next to a nested source's missing 1:1 spec --
# the direct children of the source's mirror directories -- by evidence that
# they exercise the source's constant. Files with no such evidence are dropped.
# Only the given directories are scanned (not recursively) and only plain text
# is matched, so the cost stays at one directory listing plus a read of each
# sibling and of each sibling's mirrored source.
class Evilution::SpecResolver::SiblingSpecRanker
  # Ranks, best first.
  NAMES_SUBJECT = 0   # file name or top-level describe constant is the subject
  CALLS_SUBJECT = 1   # the sibling's own subject (its mirrored source) references the subject
  MENTIONS_SUBJECT = 2 # the sibling mentions the subject constant

  DESCRIBE_PATTERN = /^\s*(?:RSpec\.)?describe\s+(?:::)?((?:[A-Z]\w*::)*[A-Z]\w*)/
  # Every constant segment, so Timeline::NightWarnings::LIMIT mentions NightWarnings.
  CONSTANT_PATTERN = /(?<!\w)[A-Z]\w*/
  MINITEST_SUFFIX = "_test.rb"
  TEST_PREFIX = "test_"

  def initialize(test_suffix:, files: Evilution::SpecResolver::ProjectFiles)
    @test_suffix = test_suffix
    @files = files
  end

  # source_path: project-relative source file (e.g. app/models/a/b/c.rb).
  # dirs: test directories to scan. Returns ranked test file paths.
  def call(source_path, dirs)
    subject = Subject.new(source_path)
    ranked = test_files_in(dirs).filter_map do |test_file|
      rank = rank_of(test_file, subject)
      [rank, test_file] if rank
    end
    ranked.sort.map(&:last)
  end

  private

  Subject = Struct.new(:source_path) do
    def name
      @name ||= File.basename(source_path, ".rb")
    end

    # Constant spelling with case and underscores folded away, so an acronym
    # (HTMLRenderer) matches its snake_case file name (html_renderer).
    def key
      @key ||= name.delete("_").downcase
    end

    def source_dir
      File.dirname(source_path)
    end

    def constant?(constant)
      constant.downcase == key
    end
  end
  private_constant :Subject

  def test_files_in(dirs)
    dirs.flat_map { |dir| globs_for(dir).flat_map { |glob| @files.glob(glob) } }.uniq.sort
  end

  def globs_for(dir)
    globs = ["#{dir}/*#{@test_suffix}"]
    globs << "#{dir}/#{TEST_PREFIX}*.rb" if @test_suffix == MINITEST_SUFFIX
    globs
  end

  def rank_of(test_file, subject)
    text = @files.read(test_file)
    return NAMES_SUBJECT if names_subject?(test_file, text, subject)
    return CALLS_SUBJECT if mentions?(@files.read(mirrored_source(test_file, subject)), subject)
    return MENTIONS_SUBJECT if mentions?(text, subject)

    nil
  end

  def names_subject?(test_file, text, subject)
    return true if stem(test_file) == subject.name

    match = text.match(DESCRIBE_PATTERN)
    return false unless match

    subject.constant?(match[1].split("::").last)
  end

  def mentions?(text, subject)
    text.scan(CONSTANT_PATTERN).any? { |constant| subject.constant?(constant) }
  end

  # The source a sibling test mirrors: same directory as the subject, named
  # after the test file (warnings_spec.rb -> <subject dir>/warnings.rb).
  def mirrored_source(test_file, subject)
    "#{subject.source_dir}/#{stem(test_file)}.rb"
  end

  def stem(test_file)
    base = File.basename(test_file)
    return base.delete_suffix(@test_suffix) if base.end_with?(@test_suffix)

    base.delete_suffix(".rb").delete_prefix(TEST_PREFIX)
  end
end
