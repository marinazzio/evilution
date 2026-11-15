# frozen_string_literal: true

require_relative "corpus"
require_relative "cost_sum"
require_relative "markdown"
require_relative "subsumption"

# The study's Markdown tables, printed to stdout.
class OperatorYield::Reports
  include OperatorYield::Markdown

  LITERAL_VARIANT_OPERATORS = %w[integer_literal string_literal float_literal].freeze
  COST_HEADER = ["removed", "returned", "killtime s", "time share", "kills", "lost kills", "survivors",
                 "survivor lines lost"].freeze
  GROUP_HEADER = ["mutants", "share", "killtime s", "time share", "killed", "survived", "timed out", "other",
                  "kill rate", "subsumed (line)", "subsumed (subject)"].freeze

  attr_reader :out

  def initialize(mutants, out: $stdout)
    @all = mutants
    @out = out
    @line_credit = OperatorYield::Subsumption.by_line(mutants)
    @subject_credit = OperatorYield::Subsumption.by_subject(mutants)
  end

  def operators = group_table(@all, :operator, "All targets, per operator")

  def variants(operator)
    group_table(@all.select { |m| m.operator == operator }, :variant, "#{operator} by variant")
  end

  def drop(selection)
    costs = by_target.to_h { |target, ms| [target, OperatorYield::DropCost.new(ms, selection)] }
    rows = costs.map { |target, cost| drop_row(target, cost) }
    heading(out, "Drop effect: #{selection}")
    table(out, ["target", "mutants", *COST_HEADER, "score before", "score after"],
          rows + [drop_total(OperatorYield::CostSum.new(costs.values))])
  end

  def drop_each(extra = [])
    specs = @all.map(&:operator).uniq + extra
    rows = specs.map { |spec| drop_each_row(spec) }.sort_by { |r| -r[4].to_f }
    heading(out, "Dropping one operator or variant at a time")
    table(out, ["operator", "generated", *COST_HEADER], rows)
  end

  def lost(selection)
    heading(out, "Lost kills: #{selection}")
    by_target.each do |target, ms|
      OperatorYield::DropCost.new(ms, selection).lost.each { |m| out.puts lost_line(target, m) }
    end
  end

  # Operator and literal-variant names the selection rule considers.
  def candidate_specs
    literals = @all.select { |m| LITERAL_VARIANT_OPERATORS.include?(m.operator) }
    @all.map(&:operator).uniq + literals.map { |m| "#{m.operator}:#{m.variant}" }.uniq
  end

  def by_target = @all.group_by(&:target)

  # Cost columns of a DropCost or CostSum, against the given total killtime.
  def cost_cells(cost, total)
    [cost.removed_count, cost.returned, seconds(cost.time), pct(cost.time, total), cost.kills, cost.lost_kills,
     cost.survivors, cost.survivor_lines_lost]
  end

  private

  def total_time = @total_time ||= @all.sum(&:duration)

  def group_table(mutants, attribute, title)
    groups = mutants.group_by(&attribute).sort_by { |_, ms| -ms.sum(&:duration) }
    rows = groups.map { |name, ms| group_row(name, ms, mutants) } + [group_row("**total**", mutants, mutants)]
    heading(out, title)
    table(out, [attribute.to_s, *GROUP_HEADER], rows)
  end

  def group_row(name, ms, all)
    time = ms.sum(&:duration)
    [name, ms.size, pct(ms.size, all.size), seconds(time), pct(time, all.sum(&:duration)), *verdicts(ms),
     *subsumed(ms)]
  end

  # killed, survived, timed out, other, kill rate
  def verdicts(ms)
    killed, survived, timed = %w[killed survived timed_out].map { |s| ms.count { |m| m.status == s } }
    judged = killed + survived + timed
    [killed, survived, timed, ms.size - judged, pct(killed + timed, judged)]
  end

  def subsumed(ms)
    with_sets = ms.select(&:kill_set?)
    return %w[– –] if with_sets.empty?

    [@line_credit, @subject_credit].map do |credit|
      pct(with_sets.sum { |m| 1.0 - credit[m] }, with_sets.size)
    end
  end

  def drop_row(target, cost)
    ms = by_target[target]
    [target, ms.size, *cost_cells(cost, ms.sum(&:duration)), score(cost.score_before), score(cost.score_after)]
  end

  def score(value) = format("%.1f%%", 100 * value)

  def drop_total(sum)
    cells = cost_cells(sum, total_time)
    cells[0] = "#{cells[0]} (#{pct(cells[0], @all.size)})"
    ["**total**", @all.size, *cells, "", ""]
  end

  def drop_each_row(spec)
    selection = OperatorYield::Selection.new([spec])
    sum = OperatorYield::CostSum.of(by_target, selection)
    [spec, @all.count { |m| selection.match?(m.operator, m.variant) }, *cost_cells(sum, total_time)]
  end

  def lost_line(target, mutant)
    ["-", target, mutant.operator, mutant.variant, mutant.line, mutant.subject,
     mutant.kills ? mutant.kills.size : "no set", mutant.diff.lines.last.strip[0, 90]].join(" | ")
  end
end
