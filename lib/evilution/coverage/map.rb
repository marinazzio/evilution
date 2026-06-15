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
    executed = (hash["executed_lines"] || {}).transform_values { |lines| lines.map(&:to_i) }
    new(index: index, built_files: hash["built_files"] || [], executed_lines: executed)
  end

  # executed_lines records, per file, the lines that ran at all during the build
  # (including lines covered only at load, e.g. a `def` line, which are
  # attributed to no single example). It lets a caller tell a TRUE coverage gap
  # (line never executed) from a load-covered line an example may still exercise
  # indirectly -- so the latter falls back instead of being mis-skipped.
  def initialize(index:, built_files:, executed_lines: {})
    @index = deep_freeze_index(index)
    @built_files = built_files.to_a.freeze
    @executed_lines = deep_freeze_executed(executed_lines)
    freeze
  end

  def examples_for(file, line)
    @index.dig(file, line) || []
  end

  def built?(file)
    @built_files.include?(file)
  end

  def executed?(file, line)
    lines = @executed_lines[file]
    !lines.nil? && lines.include?(line)
  end

  def to_h
    { "index" => @index, "built_files" => @built_files, "executed_lines" => @executed_lines }
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

  def deep_freeze_executed(executed)
    executed.each_with_object({}) do |(file, lines), out|
      out[file] = lines.map(&:to_i).uniq.sort.freeze
    end.freeze
  end
end
