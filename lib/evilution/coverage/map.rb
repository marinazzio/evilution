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
    new(index: index, built_files: hash["built_files"] || [], executed_lines: hash["executed_lines"] || {},
        missed_lines: hash["missed_lines"] || {}, spec_files: hash["spec_files"].to_a)
  end

  # executed_lines records, per file, the lines that ran at all during the build
  # (including lines covered only at load, e.g. a `def` line, which are
  # attributed to no single example). It lets a caller tell a TRUE coverage gap
  # (line never executed) from a load-covered line an example may still exercise
  # indirectly -- so the latter falls back instead of being mis-skipped.
  #
  # missed_lines records, per file, the executable lines that never ran at all,
  # neither while the files loaded nor in any example. A file is listed only
  # when the build vouches for it: every example of the spec files ran, and the
  # file's load was counted. spec_files are the spec files the build ran.
  def initialize(index:, built_files:, executed_lines: {}, missed_lines: {}, spec_files: [])
    @index = deep_freeze_index(index)
    @built_files = built_files.to_a.freeze
    @executed_lines = deep_freeze_executed(executed_lines)
    @missed_lines = deep_freeze_executed(missed_lines)
    @spec_files = spec_files.to_a.freeze
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

  # Whether no example and no file load executed any of these lines: at least
  # one of them is an executable line that never ran, and none of them ran. A
  # line that is not executable (an `end`, a continuation) says nothing either
  # way, so lines made only of those are not uncovered.
  def uncovered?(file, lines)
    missed = @missed_lines[file]
    return false if missed.nil?
    return false if lines.any? { |line| executed?(file, line) }

    lines.any? { |line| missed.include?(line) }
  end

  # Whether the build ran every one of these spec files, so what it saw is
  # what a run of them would see.
  def built_from?(spec_files)
    !spec_files.empty? && spec_files.all? { |file| @spec_files.include?(file) }
  end

  def to_h
    {
      "index" => @index, "built_files" => @built_files, "executed_lines" => @executed_lines,
      "missed_lines" => @missed_lines, "spec_files" => @spec_files
    }
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
