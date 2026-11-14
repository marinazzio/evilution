# frozen_string_literal: true

require "digest"
require_relative "../cache"
require_relative "../related_spec_heuristic"
require_relative "skeleton"
require_relative "spec_digest"
require_relative "run_fingerprint"

# The keys a mutation's verdict is cached under.
#
# The subject key stands for everything the verdict of any mutation of one
# subject depends on that the cache can see: the run's fingerprint (settings,
# versions, spec helpers), the subject's own source, the rest of its file
# outside every subject (see Skeleton), and the spec files that resolve for
# the file. Editing one method changes only that method's key.
#
# The mutation key tells the mutations of one subject apart. It is counted
# from the subject rather than from the top of the file, so a subject that
# only moved, because lines were added above it, keeps its verdicts.
#
# Neither key sees the other methods a subject calls, other source files, or
# what spec files load beyond the conventional helpers; a change there keeps
# the cached verdicts. Constants are the exception within the file: they stay
# part of the skeleton.
class Evilution::Cache::Keys
  CONSTANT_KINDS = %i[constant constant_write].freeze
  private_constant :CONSTANT_KINDS

  def self.for(config)
    new(
      fingerprint: Evilution::Cache::RunFingerprint.new(config),
      spec_selector: config.spec_selector,
      related_specs: config.related_specs_heuristic? ? Evilution::RelatedSpecHeuristic.new : nil
    )
  end

  # spec_selector: answers the spec files run for a source file.
  # related_specs: answers the spec files the related-specs heuristic adds
  # for a mutation, when it is on.
  def initialize(fingerprint:, spec_selector:, related_specs: nil, spec_digest: Evilution::Cache::SpecDigest.new)
    @fingerprint = fingerprint
    @spec_selector = spec_selector
    @related_specs = related_specs
    @spec_digest = spec_digest
    @spans = {}
    @names = {}
    @skeletons = {}
    @subject_keys = {}.compare_by_identity
  end

  # Every subject parsed from the run's files, before any is filtered out:
  # the skeleton leaves out all of them, whichever this run mutates, except
  # constants. A constant is read by the methods around it, so editing one
  # changes the key of every subject in its file.
  def index(subjects)
    subjects.group_by(&:file_path).each do |file_path, file_subjects|
      @spans[file_path] = file_subjects.reject { |subject| CONSTANT_KINDS.include?(subject.kind) }.map(&:byte_range)
      @names[file_path] = file_subjects.map(&:name)
    end
  end

  def subject_names(file_path)
    @names[file_path]
  end

  # nil when the mutation cannot be keyed: its sources were released, or no
  # spec file resolves for its file.
  def subject_key(mutation)
    source = mutation.original_source
    return nil if source.nil?

    subject = mutation.subject
    return @subject_keys[subject] if @subject_keys.key?(subject)

    @subject_keys[subject] = build_subject_key(mutation, subject, source)
  end

  def mutation_key(mutation)
    return nil if mutation.mutated_source.nil?

    first_line = mutation.changed_lines.first - mutation.subject.line_number
    key = [mutation.operator_name, first_line, edit_digest(mutation)].join(":")
    related = related_digest(mutation)
    related ? "#{key}:#{related}" : key
  end

  private

  def build_subject_key(mutation, subject, source)
    specs = @spec_digest.call(@spec_selector.call(mutation.file_path))
    return nil unless specs

    Digest::SHA256.hexdigest(
      [@fingerprint.to_s, mutation.file_path, subject.name, skeleton(mutation.file_path, source),
       Digest::SHA256.hexdigest(subject.source), specs].join("\0")
    )
  end

  def skeleton(file_path, source)
    @skeletons[file_path] ||= Evilution::Cache::Skeleton.digest(source, @spans.fetch(file_path, []))
  end

  # The affected lines before and after, which with the line the edit starts
  # on fix the mutated file. A mutation built without them falls back to the
  # whole mutated file.
  def edit_digest(mutation)
    original = mutation.original_slice
    mutated = mutation.mutated_slice
    text = original && mutated ? "#{original}\0#{mutated}" : mutation.mutated_source
    Digest::SHA256.hexdigest(text)[0, 16]
  end

  def related_digest(mutation)
    return nil unless @related_specs

    digest = @spec_digest.call(@related_specs.call(mutation))
    digest && digest[0, 16]
  end
end
