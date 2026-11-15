# frozen_string_literal: true

# Compares the A/B runs of run_study.sh (mode ab): the default operator set
# ("off") against the default set minus DROP_SET ("on").
#
#   ruby scripts/operator_yield/ab_compare.rb <dir> <drop set>
#
# Prints a table of mutant count, killtime, wall time (mean of the repeats,
# from wall.log) and score per target, and which operator reports a dropped
# operator's mutant in the "on" run when another operator generates the same
# code (matched by file, line and diff).
require "json"
require_relative "variants"
require_relative "lib/markdown"
require_relative "lib/selection"

class OperatorYield::ABCompare
  include OperatorYield::Markdown

  HEADER = ["target", "mutants off", "mutants on", "Δ mutants", "killtime off s", "killtime on s", "Δ killtime",
            "wall off s", "wall on s", "Δ wall", "killed mutants removed", "score off", "score on"].freeze
  Side = Data.define(:summary, :mutants, :walls) do
    def total = summary["total"]
    def killtime = summary["killtime"]
    def wall = walls.sum / walls.size
    def score = format("%.1f%%", 100.0 * summary["score"])
    def wall_cell = "#{wall.round(1)} (#{walls.map { |w| w.round(1) }.join(", ")})"
    def by_site = mutants.to_h { |m| [[m["file"], m["line"], m["diff"]], m] }
  end

  def initialize(dir, selection, out: $stdout)
    @dir = dir
    @selection = selection
    @out = out
    @walls = read_walls
    @sides = targets.to_h { |t| [t, %w[off on].map { |side| load(t, side) }] }
  end

  def call
    rows = @sides.map { |target, (off, on)| row(target, off, on) }
    table(@out, HEADER, rows + [total])
    returns
    0
  end

  private

  def read_walls
    walls = Hash.new { |h, k| h[k] = [] }
    File.foreach(File.join(@dir, "wall.log")) do |l|
      m = l.match(/(\S+) (off|on) (\d+) wall=([\d.]+)/)
      walls[[m[1], m[2]]] << m[4].to_f if m
    end
    walls
  end

  def targets = @walls.keys.map(&:first).uniq

  def load(target, side)
    report = JSON.parse(File.read(File.join(@dir, "#{target}-#{side}-1.json")))
    Side.new(summary: report["summary"], mutants: OperatorYield.entries(report), walls: @walls[[target, side]])
  end

  def change(from, to) = format("%+.1f%%", 100.0 * (to - from) / from)

  def changes(off, on, attribute)
    from = off.public_send(attribute)
    to = on.public_send(attribute)
    [from, to, change(from, to)]
  end

  def row(target, off, on)
    [target, *changes(off, on, :total), *changes(off, on, :killtime).then { |a, b, c| [a.round(1), b.round(1), c] },
     off.wall_cell, on.wall_cell, change(off.wall, on.wall), killed_removed(off, on), off.score, on.score]
  end

  # Killed mutants of the "off" run whose code the "on" run no longer has,
  # whichever operator reports it.
  def killed_removed(off, on)
    on_sites = on.by_site
    off.by_site.count { |site, m| %w[killed timed_out].include?(m["status"]) && !on_sites.key?(site) }
  end

  def total
    removed = @sides.values.sum { |off, on| killed_removed(off, on) }
    ["**total**", *sum_change(:total), *sum_change(:killtime), *sum_change(:wall), removed, "", ""]
  end

  # off, on and the change of an attribute summed over the targets
  def sum_change(attribute)
    off, on = [0, 1].map { |i| @sides.values.sum { |pair| pair[i].public_send(attribute) } }
    off.is_a?(Float) ? [off.round(1), on.round(1), change(off, on)] : [off, on, change(off, on)]
  end

  # Dropped operators' mutants of the "off" run that the "on" run still has,
  # by the operator that reports them there.
  def returns
    moves = Hash.new(0)
    @sides.each_value { |off, on| count_moves(off, on, moves) }
    @out.puts
    table(@out, ["dropped operator -> reported in the on run as", "mutants"], moves.sort)
  end

  def count_moves(off, on, moves)
    on_sites = on.by_site
    off.by_site.each do |site, m|
      next unless @selection.match?(m["operator"], Variants.of(m["operator"], m["diff"]))

      moves["#{m["operator"]} -> #{on_sites.key?(site) ? on_sites[site]["operator"] : "(removed)"}"] += 1
    end
  end
end

exit OperatorYield::ABCompare.new(ARGV[0], OperatorYield::Selection.new(ARGV[1].split(","))).call if __FILE__ == $PROGRAM_NAME
