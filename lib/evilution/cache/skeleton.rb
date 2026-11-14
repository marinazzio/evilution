# frozen_string_literal: true

require "digest"
require_relative "../cache"

# A digest of what a source file holds outside its subjects: the class and
# module lines, constants no subject owns, `include`s, `attr_*`s and other
# class-body code. Editing a method leaves it unchanged; editing anything
# its subjects do not cover changes it.
#
# Each removed span is marked where it was, so text cannot move from one
# side of a subject to the other unnoticed. Without a span for every subject
# the whole file is digested, which is what the cache keyed on before
# subjects had keys of their own.
module Evilution::Cache::Skeleton
  SEPARATOR = "\0"
  private_constant :SEPARATOR

  def self.digest(source, spans)
    bytes = source.b
    merged = merge(spans, bytes.bytesize)
    return Digest::SHA256.hexdigest(bytes) unless merged

    Digest::SHA256.hexdigest(outside(bytes, merged))
  end

  # The spans in order with overlapping and nested ones folded together, or
  # nil when one is unknown or does not fit the file.
  def self.merge(spans, size)
    return nil unless spans.all? { |span| span.is_a?(Range) && span.end <= size }

    spans.sort_by(&:begin).each_with_object([]) { |span, merged| fold(merged, span) }
  end
  private_class_method :merge

  def self.fold(merged, span)
    last = merged.last
    if last && span.begin < last.end
      merged[-1] = last.begin...[last.end, span.end].max
    else
      merged << (span.begin...span.end)
    end
  end
  private_class_method :fold

  def self.outside(bytes, spans)
    kept = +""
    cursor = 0
    spans.each do |span|
      kept << bytes.byteslice(cursor, span.begin - cursor) << SEPARATOR
      cursor = span.end
    end
    kept << bytes.byteslice(cursor, bytes.bytesize - cursor)
  end
  private_class_method :outside
end
