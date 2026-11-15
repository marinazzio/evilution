# frozen_string_literal: true

# Operator yield analysis over a study directory written by run_study.sh.
#
#   ruby scripts/operator_yield/analyze.rb <dir> <target>... [options]
#
#   --variants op1,op2   per-variant table of these operators
#   --drop spec          cost of dropping a set, per target ("op,op:variant");
#                        repeatable
#   --drop-each [specs]  one row per operator (and per extra spec given)
#   --loto               leave-one-target-out selection rule (--min N, default 20)
#   --lost spec          the kills a set loses, one line each
#
# The per-operator table is always printed. Load statistics go to stderr.
require_relative "lib/reports"
require_relative "lib/selection_rule"

class OperatorYield::CLI
  def initialize(argv)
    @dir = argv.shift
    @targets = []
    @actions = []
    @min = 20
    parse(argv)
  end

  def call
    reports = OperatorYield::Reports.new(load_mutants)
    reports.operators
    @actions.each { |action, arg| run(reports, action, arg) }
    0
  end

  private

  def parse(argv)
    while (arg = argv.shift)
      case arg
      when "--variants", "--drop", "--lost" then @actions << [arg.delete_prefix("--").to_sym, argv.shift]
      when "--drop-each" then @actions << [:drop_each, optional_value(argv)]
      when "--loto" then @actions << [:loto, nil]
      when "--min" then @min = Integer(argv.shift)
      else @targets << arg
      end
    end
  end

  def optional_value(argv) = argv.empty? || argv.first.start_with?("--") ? nil : argv.shift

  def load_mutants
    @targets.flat_map do |target|
      corpus = OperatorYield::Corpus.new(@dir, target)
      s = corpus.summary
      warn "#{target}: #{corpus.mutants.size} mutants, killed #{s["killed"]}, survived #{s["survived"]}, " \
           "killtime #{s["killtime"]}, kill-set verdict mismatches #{corpus.verdict_mismatches}, " \
           "killed without kill set #{corpus.killed_without_set}"
      corpus.mutants
    end
  end

  def run(reports, action, arg)
    case action
    when :variants then arg.split(",").each { |op| reports.variants(op) }
    when :drop then reports.drop(OperatorYield::Selection.new(arg.split(",")))
    when :drop_each then reports.drop_each(arg.to_s.split(","))
    when :lost then reports.lost(OperatorYield::Selection.new(arg.split(",")))
    when :loto then OperatorYield::SelectionRule.new(reports, min: @min).call
    end
  end
end

exit OperatorYield::CLI.new(ARGV.dup).call if __FILE__ == $PROGRAM_NAME
