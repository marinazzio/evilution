# frozen_string_literal: true

require_relative "../loading"
require_relative "../../ast/source_surgeon"

# A file's source with its class-body calls neutralized (see
# BodyCallNeutralizer), and the edits that made it from the file:
# [start offset, end offset, replacement], in order.
#
# A mutation made where no edit is changes nothing the edits depend on as
# long as it adds no class body of its own, which the caller checks: the
# mutated file then neutralizes to this source with the mutation spliced in,
# and #carry builds that without parsing the mutated file.
class Evilution::Integration::Loading::Neutralization
  attr_reader :source, :edits

  # edits: nil when the file could not be neutralized, so nothing can be
  # carried into it.
  def initialize(source:, edits:)
    @source = source
    @edits = edits
    freeze
  end

  # The neutralized mutated file, for a mutation made inside span (a range
  # of offsets in the file), or nil when an edit touches the span.
  def carry(span, offset:, length:, replacement:, mutated:)
    return if @edits.nil? || @edits.any? { |from, to, _| from <= span.end && to >= span.begin }
    return mutated if @edits.empty?

    Evilution::AST::SourceSurgeon.splice(@source, offset: offset + shift_before(span.begin), length: length,
                                                  replacement: replacement)
  end

  private

  # How far the edits before an offset move it in the neutralized source.
  def shift_before(offset)
    @edits.sum { |from, to, replacement| to < offset ? replacement.bytesize - (to - from) : 0 }
  end
end
