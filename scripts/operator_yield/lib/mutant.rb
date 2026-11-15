# frozen_string_literal: true

module OperatorYield
  BUCKETS = %w[killed survived timed_out errors neutral equivalent unresolved unparseable uncovered].freeze

  module_function

  def entries(report) = BUCKETS.flat_map { |b| Array(report[b]) }

  def key_of(row) = [row["file"], row["line"], row["operator"], row["diff"]]
end

# One mutant of a study run. kills: ids of every test that failed on it (from
# the kill-set run). alternatives: [operator, variant] of the other operators
# that generate the same mutated file; the planner keeps the first one only,
# so dropping this mutant's operator brings it back under one of them.
OperatorYield::Mutant = Struct.new(:target, :file, :line, :operator, :variant, :diff, :status, :duration, :subject,
                                   :kills, :alternatives, keyword_init: true) do
  def key = [file, line, operator, diff]
  def detected? = %w[killed timed_out].include?(status)
  def judged? = %w[killed survived timed_out].include?(status)
  def survived? = status == "survived"
  def kill_set? = status == "killed" && kills && !kills.empty?
  def file_line = [file, line]
end
