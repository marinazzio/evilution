# frozen_string_literal: true

require_relative "../ast/inheritance_scanner"
require_relative "../git/changed_files"

class Evilution::Runner; end unless defined?(Evilution::Runner) # rubocop:disable Lint/EmptyClass

class Evilution::Runner::SubjectPipeline
  def initialize(config, parser:)
    @config = config
    @parser = parser
  end

  def call
    subjects = parse_subjects
    subjects = filter_by_descendants(subjects) if descendants_target?
    subjects = filter_by_target(subjects) if method_target?
    subjects = filter_by_line_ranges(subjects) if config.line_ranges?
    subjects
  end

  def target_files
    @target_files ||= resolve_target_files
  end

  private

  attr_reader :config, :parser

  def parse_subjects
    target_files.flat_map { |file| parser.call(file) }
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
    if target.end_with?("*")
      prefix = target.chomp("*")
      ->(s) { s.name.split(/[#.]/).first.start_with?(prefix) }
    elsif target.end_with?("#", ".")
      prefix = target
      ->(s) { s.name.start_with?(prefix) }
    elsif target.include?("#") || target.include?(".")
      ->(s) { s.name == target }
    else
      ->(s) { s.name.start_with?("#{target}#") || s.name.start_with?("#{target}.") }
    end
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
