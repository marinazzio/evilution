# frozen_string_literal: true

require_relative "../subject_pipeline"

# What `--target` asks for, read once from the text the user gave:
#
#   source:lib/**/*.rb   the files of a glob
#   descendants:Base     a class and everything inheriting from it
#   User#adult?          a method; `User`, `User#`, `Billing::*` for several
#
# NONE stands in when no target was given: it is no kind of target and
# selects every subject, so the pipeline never has to ask whether there is
# one.
class Evilution::Runner::SubjectPipeline::Target
  PREFIXES = { "source:" => :source_glob, "descendants:" => :descendants }.freeze
  private_constant :PREFIXES

  def self.parse(text)
    return NONE if text.nil?

    prefix, kind = PREFIXES.find { |candidate, _| text.start_with?(candidate) }
    return new(kind: :method, text: text, value: text) if prefix.nil?

    new(kind: kind, text: text, value: text.delete_prefix(prefix))
  end

  # The part after the prefix: the glob, the base class name, or the method
  # name as written.
  attr_reader :value

  def initialize(kind:, text:, value:)
    @kind = kind
    @text = text
    @value = value
  end

  def source_glob?
    @kind == :source_glob
  end

  def descendants?
    @kind == :descendants
  end

  def method?
    @kind == :method
  end

  # The target as the user wrote it, for messages.
  def to_s
    @text.to_s
  end

  # Only a method target narrows subjects by name.
  def selects?(subject)
    !method? || matcher.call(subject.name)
  end

  NONE = new(kind: :none, text: nil, value: nil)

  private

  def matcher
    @matcher ||= build_matcher
  end

  def build_matcher
    return wildcard_matcher(value.chomp("*")) if value.end_with?("*")
    return prefix_matcher(value) if value.end_with?("#", ".")

    name_matcher(value)
  end

  def wildcard_matcher(prefix)
    ->(name) { name.split(/[#.]/).first.start_with?(prefix) }
  end

  def prefix_matcher(prefix)
    ->(name) { name.start_with?(prefix) }
  end

  # A full method name matches itself; a class name, each of its methods.
  def name_matcher(target)
    ->(name) { name == target || name.start_with?("#{target}#") || name.start_with?("#{target}.") }
  end
end
