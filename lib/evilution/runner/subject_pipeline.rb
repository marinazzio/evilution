# frozen_string_literal: true

require_relative "../runner"
require_relative "../ast/inheritance_scanner"
require_relative "../ast/uncovered_code"
require_relative "../diagnostic"
require_relative "../git/changed_files"

class Evilution::Runner::SubjectPipeline
  def initialize(config, parser:)
    @config = config
    @parser = parser
  end

  def call
    subjects = parse_subjects
    report_uncovered_code(subjects)
    subjects = filter_by_descendants(subjects) if descendants_target?
    subjects = filter_by_target(subjects) if method_target?
    subjects = filter_by_line_ranges(subjects) if config.line_ranges?
    subjects
  end

  def target_files
    @target_files ||= resolve_target_files
  end

  # The targeted lines that hold code outside every subject, as
  # `{ file:, lines: ["2-4", "9"] }` per file, once #call has run.
  def uncovered_code
    @uncovered_code || []
  end

  private

  attr_reader :config, :parser

  def parse_subjects
    target_files.flat_map { |file| parser.call(file) }
  end

  # A line range is checked as given; a whole file only when it has no
  # subjects at all -- every class with an `include` or a constant would
  # otherwise warn.
  def report_uncovered_code(subjects)
    by_file = subjects.group_by(&:file_path)
    @uncovered_code = target_files.filter_map { |file| uncovered_entry(file, by_file.fetch(file, [])) }
    @uncovered_code.each { |entry| warn_uncovered(entry) }
  end

  def uncovered_entry(file, file_subjects)
    range = config.line_ranges[file]
    return unless range || file_subjects.empty?

    lines = Evilution::AST::UncoveredCode.call(file, file_subjects, lines: range)
    { file: file, lines: lines.map { |run| line_label(run) } } unless lines.empty?
  end

  # Spelled the way a range is passed on the command line: `2-4`, or `9`.
  def line_label(run)
    run.size == 1 ? run.first.to_s : "#{run.first}-#{run.last}"
  end

  def warn_uncovered(entry)
    Evilution::Diagnostic.warn(
      "[evilution] #{entry[:file]}:#{entry[:lines].join(", ")} holds code outside every subject " \
      "(class-body code such as DSL calls and constants is not mutated); no mutations target those lines."
    )
  end

  def source_glob_target?
    config.target&.start_with?("source:")
  end

  def descendants_target?
    config.target&.start_with?("descendants:")
  end

  def method_target?
    config.target? && !source_glob_target? && !descendants_target?
  end

  def resolve_source_glob
    pattern = config.target.delete_prefix("source:")
    files = Dir.glob(pattern)
    raise Evilution::Error, "no files found matching '#{pattern}'" if files.empty?

    files.sort
  end

  def filter_by_descendants(subjects)
    base_name = config.target.delete_prefix("descendants:")
    inheritance = Evilution::AST::InheritanceScanner.call(target_files)
    class_names = resolve_descendant_set(base_name, inheritance)
    raise Evilution::Error, "no classes found matching '#{config.target}'" if class_names.empty?

    subjects.select { |s| class_names.include?(s.name.split(/[#.]/).first) }
  end

  def resolve_descendant_set(base_name, inheritance)
    descendants = Set.new
    known = inheritance.key?(base_name) || inheritance.value?(base_name)
    return descendants unless known

    descendants.add(base_name)
    changed = true
    while changed
      changed = false
      inheritance.each do |child, parent|
        next unless descendants.include?(parent)
        next if descendants.include?(child)

        descendants.add(child)
        changed = true
      end
    end
    descendants
  end

  def filter_by_target(subjects)
    matched = subjects.select(&target_matcher)
    raise Evilution::Error, build_no_match_error if matched.empty?

    matched
  end

  def resolve_target_files
    return resolve_source_glob if source_glob_target?
    return config.target_files unless config.target_files.empty?

    @used_git_fallback = true
    Evilution::Git::ChangedFiles.new.call
  end

  def build_no_match_error
    base = "no subject matched '#{config.target}'"
    return base unless @used_git_fallback

    "#{base}; scanned git-changed files only. Pass file paths or " \
      "--target source:<glob> to scan the full codebase."
  end

  def target_matcher
    target = config.target
    return wildcard_matcher(target.chomp("*")) if target.end_with?("*")
    return prefix_matcher(target) if target.end_with?("#", ".")
    return exact_matcher(target) if target.include?("#") || target.include?(".")

    class_matcher(target)
  end

  def wildcard_matcher(prefix)
    ->(s) { s.name.split(/[#.]/).first.start_with?(prefix) }
  end

  def prefix_matcher(prefix)
    ->(s) { s.name.start_with?(prefix) }
  end

  def exact_matcher(target)
    ->(s) { s.name == target }
  end

  def class_matcher(target)
    ->(s) { s.name == target || s.name.start_with?("#{target}#") || s.name.start_with?("#{target}.") }
  end

  def filter_by_line_ranges(subjects)
    subjects.select do |subject|
      range = config.line_ranges[subject.file_path]
      next true unless range

      subject_start = subject.line_number
      subject_end = subject_start + subject.source.count("\n")
      subject_start <= range.last && subject_end >= range.first
    end
  end
end
