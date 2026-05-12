# frozen_string_literal: true

require "prism"
require_relative "../loading"

# Replace just the mutated method body on the live owner class instead of
# re-eval'ing the whole file. Skips re-executing class-body statements
# (registries, mixin registration, define_method side effects) that don't
# tolerate being run twice in the same process.
#
# Falls back to :not_applicable for non-DefNode subjects, unresolvable owners,
# or when the named method is missing from the mutated source — caller is
# expected to dispatch to SourceEvaluator in those cases.
class Evilution::Integration::Loading::MethodSpliceEvaluator
  INSTANCE_SEP = "#"
  SINGLETON_SEP = "."

  def call(mutation)
    target = resolve_splice_target(mutation)
    return :not_applicable unless target

    target.owner.class_eval(target.def_source, target.file_path, target.line)
    :spliced
  end

  private

  SpliceTarget = Data.define(:owner, :def_source, :file_path, :line)
  private_constant :SpliceTarget

  def resolve_splice_target(mutation)
    return nil unless mutation.respond_to?(:subject)

    subject = mutation.subject
    return nil if subject.nil?

    owner_name, method_name = split_subject_name(subject.name)
    return nil unless owner_name && method_name

    owner = resolve_constant(owner_name)
    return nil unless owner

    def_node = locate_def_in_mutated(mutation.mutated_source, method_name, subject.line_number)
    return nil unless def_node

    build_splice_target(owner, def_node, mutation)
  end

  def build_splice_target(owner, def_node, mutation)
    loc = def_node.location
    def_source = mutation.mutated_source.byteslice(loc.start_offset, loc.end_offset - loc.start_offset)
    SpliceTarget.new(owner: owner, def_source: def_source, file_path: mutation.file_path, line: loc.start_line)
  end

  def split_subject_name(name)
    if name.include?(INSTANCE_SEP)
      name.split(INSTANCE_SEP, 2)
    elsif name.include?(SINGLETON_SEP)
      name.split(SINGLETON_SEP, 2)
    else
      [nil, nil]
    end
  end

  def resolve_constant(qualified)
    qualified = qualified.sub(/\A::/, "")
    qualified.split("::").reduce(Object) do |mod, part|
      return nil unless mod.const_defined?(part, false)

      mod.const_get(part, false)
    end
  end

  def locate_def_in_mutated(source, method_name, target_line)
    tree = Prism.parse(source)
    return nil unless tree.success?

    finder = DefFinder.new(method_name.to_sym, target_line)
    finder.visit(tree.value)
    finder.match
  end

  class DefFinder < Prism::Visitor
    attr_reader :match

    def initialize(method_name, target_line)
      @method_name = method_name
      @target_line = target_line
      @match = nil
      @best_distance = nil
    end

    def visit_def_node(node)
      if node.name == @method_name
        distance = (node.location.start_line - @target_line).abs
        if @best_distance.nil? || distance < @best_distance
          @match = node
          @best_distance = distance
        end
      end
      super
    end
  end
  private_constant :DefFinder
end
