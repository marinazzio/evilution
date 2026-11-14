# frozen_string_literal: true

require_relative "../mutator"
require_relative "restore_source_cache"

# The two sources a worker evaluates for a mutation of a subject's file: the
# mutated file, to load the mutation, and the original, to put the file back
# after the mutation's tests. Both have their class-body calls neutralized
# (see Integration::Loading::BodyCallNeutralizer).
class Evilution::Mutator::LoadSources
  # Subjects whose body is written inside a class-body declaration and only
  # takes effect when that declaration runs again.
  REDECLARED_KINDS = %i[scope aasm callback].freeze
  private_constant :REDECLARED_KINDS

  def initialize(subject, file_source, neutralizer)
    @subject = subject
    @file_source = file_source
    @neutralizer = neutralizer
  end

  # Pre-compute the worker's eval target so per-iter Prism re-parse cost
  # stays out of the hot path. For parseable mutations we strip class/module
  # body calls that are known to be non-idempotent (registries etc.); for
  # unparseable bytes we fall through so the syntax validator can reject
  # them at apply time. Passing the subject's file path lets the neutralizer
  # skip files the parent never preloaded — those are lazy plugin files whose
  # DSL calls are still needed for the child fork's first-time load.
  # A scope or aasm subject's mutation sits inside a class-body declaration,
  # which must run again for the mutated body to replace the loaded one, so
  # that one declaration is kept.
  def eval_source(surgery, offset)
    return surgery.source unless surgery.ok?

    carried_eval_source(surgery) ||
      @neutralizer.call(surgery.source, file_path: @subject.file_path, **redeclaration(offset))
  end

  # The original file, evaluated after a mutation's tests to put back what
  # the mutation changed. Without it an in-process run would leave the last
  # mutation of a file applied while the files after it are mutated, failing
  # their tests for them. Its class-body calls are neutralized like the eval
  # source's; a scope, aasm or callback subject keeps its own declaration, so
  # the mutated callable is declared over again as written.
  def restore_source(offset)
    return neutralization.source unless redeclared_subject?

    @neutralizer.call(@file_source, file_path: @subject.file_path, **redeclaration(offset))
  end

  private

  # A mutation the method alone was parsed for (see AST::DefRegion) leaves
  # the rest of the file as it was, so its class-body calls are the
  # original's: unless one of them holds the method, or the mutated method
  # holds a class body of its own, the original's neutralization with the
  # mutation spliced in is what neutralizing the mutated file would give,
  # without parsing it.
  def carried_eval_source(surgery)
    region = surgery.region
    return if region.nil? || redeclared_subject? || !@neutralizer.blanks_nothing_in?(region.node)

    neutralization.carry(region.span, offset: region.offset, length: region.length,
                                      replacement: region.replacement, mutated: surgery.source)
  end

  def neutralization
    Evilution::Mutator::RestoreSourceCache.neutralization_for(@subject.file_path, @file_source, @neutralizer)
  end

  # So is anything written in a concern's hook block, a method included: the
  # block has to run again on the classes that took the concern already.
  def redeclared_subject?
    REDECLARED_KINDS.include?(@subject.kind) || @subject.concern_hook?
  end

  # What the neutralizer needs to keep a redeclared subject's declaration:
  # where the mutation is, the lines the declaration takes up in the file as
  # it was loaded -- which is where the callbacks it registered then say they
  # come from, whatever the mutation does to its length -- and the
  # declaration as written there.
  def redeclaration(offset)
    return {} unless redeclared_subject?

    first = @subject.line_number
    { keep_offset: offset, keep_lines: first..(first + @subject.source.count("\n")), keep_source: @subject.source }
  end
end
