# frozen_string_literal: true

require_relative "selection"

# What dropping a selection costs on one target's mutants:
# - lost kills: removed killed mutants for which no kept mutant of the same
#   subject has a non-empty kill set contained in theirs, plus removed
#   timeouts and load-time kills (no failing example: never subsumed);
# - survivor lines lost: lines where a removed mutant survived and no kept
#   mutant survives.
class OperatorYield::DropCost
  attr_reader :removed, :kept, :returned

  def initialize(mutants, selection)
    @mutants = mutants
    @returned = mutants.count { |m| selection.returns?(m) }
    @removed, @kept = mutants.partition { |m| selection.removes?(m) }
  end

  def removed_count = removed.size
  def time = removed.sum(&:duration)
  def kills = removed.count(&:detected?)
  def survivors = removed.count(&:survived?)

  def lost_kills = lost.size

  def lost
    by_subject = kept.select(&:kill_set?).group_by(&:subject)
    removed.select do |m|
      next false unless m.detected?
      next true unless m.kill_set?

      by_subject.fetch(m.subject, []).none? { |k| k.kills.subset?(m.kills) }
    end
  end

  def survivor_lines_lost
    kept_lines = kept.select(&:survived?).to_set(&:file_line)
    removed.select(&:survived?).map(&:file_line).uniq.count { |fl| !kept_lines.include?(fl) }
  end

  def score_before = score(@mutants)
  def score_after = score(kept)

  private

  def score(list)
    judged = list.count(&:judged?)
    judged.zero? ? 0.0 : list.count(&:detected?).fdiv(judged)
  end
end
