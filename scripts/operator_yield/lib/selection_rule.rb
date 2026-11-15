# frozen_string_literal: true

require_relative "cost_sum"
require_relative "markdown"

# Leave-one-group-out check of a selection rule: on the training groups, pick
# every operator / literal variant that removes >= min mutants and whose
# drop-alone cost is 0 lost kills and 0 survivor lines lost; then drop the
# picked set jointly on the held-out group. The fixture targets (fx-*) are
# one group. Prints the folds and returns the specs picked in every fold.
class OperatorYield::SelectionRule
  include OperatorYield::Markdown

  def initialize(reports, min:)
    @reports = reports
    @min = min
    @groups = reports.by_target.group_by { |target, _| target.sub(/\Afx-.*/, "fx") }.transform_values(&:to_h)
    @specs = reports.candidate_specs
  end

  def call
    picks = @groups.keys.to_h { |held| [held, pick(training_without(held))] }
    print_folds(picks)
    common = in_every_fold(picks.values)
    @reports.out.puts "\nPicked in every fold: #{common.join(",")}"
    common
  end

  private

  def print_folds(picks)
    out = @reports.out
    heading(out, "Leave-one-target-out (min #{@min} removed mutants)")
    table(out, ["held out", "picked", "removed on held-out", "time share", "kills", "lost kills", "survivors",
                "survivor lines lost"], picks.map { |held, picked| fold_row(held, picked) })
    picks.each { |held, picked| out.puts "\n- without #{held}: #{picked.sort.join(", ")}" }
  end

  def training_without(held) = @groups.reject { |g, _| g == held }.values.reduce({}, :merge)

  def pick(training)
    picked = @specs.select do |spec|
      sum = OperatorYield::CostSum.of(training, OperatorYield::Selection.new([spec]))
      sum.removed_count >= @min && sum.lost_kills.zero? && sum.survivor_lines_lost.zero?
    end
    # A variant is covered when its operator is picked.
    picked.reject { |spec| spec.include?(":") && picked.include?(spec.split(":").first) }
  end

  def fold_row(held, picked)
    targets = @groups[held]
    sum = OperatorYield::CostSum.of(targets, OperatorYield::Selection.new(picked))
    all = targets.values.flatten
    # time share, kills, lost kills, survivors, survivor lines lost
    cells = @reports.cost_cells(sum, all.sum(&:duration)).drop(3)
    [held, picked.size, "#{sum.removed_count} / #{all.size}", *cells]
  end

  # Specs picked in every fold, an operator pick standing for its variants.
  def in_every_fold(picks)
    common = picks.flatten.uniq.select do |spec|
      picks.all? { |p| p.include?(spec) || p.include?(spec.split(":").first) }
    end
    common.reject { |spec| spec.include?(":") && common.include?(spec.split(":").first) }.sort
  end
end
