# frozen_string_literal: true

require_relative "../coverage"

# Immutable query over a per-example line-coverage index:
#   source file -> line -> [example locations ("spec.rb:line")].
# built_files records the source files for which the build completed, so
# callers can distinguish "line genuinely uncovered" (file built, no entry)
# from "we never built this file" (must fall back, not assert a gap).
class Evilution::Coverage::Map
  def self.from_h(hash)
    index = (hash["index"] || {}).transform_values do |lines|
      lines.transform_keys(&:to_i)
    end
    new(index: index, built_files: hash["built_files"] || [])
  end

  def initialize(index:, built_files:)
    @index = deep_freeze_index(index)
    @built_files = built_files.to_a.freeze
    freeze
  end

  def examples_for(file, line)
    @index.dig(file, line) || []
  end

  def built?(file)
    @built_files.include?(file)
  end

  def to_h
    { "index" => @index, "built_files" => @built_files }
  end

  private

  def deep_freeze_index(index)
    index.each_with_object({}) do |(file, lines), out|
      frozen_lines = lines.each_with_object({}) do |(line, locs), inner|
        inner[line] = locs.uniq.sort.freeze
      end
      out[file] = frozen_lines.freeze
    end.freeze
  end
end
