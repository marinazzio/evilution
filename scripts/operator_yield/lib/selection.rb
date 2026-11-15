# frozen_string_literal: true

require_relative "mutant"

# A set of operators and operator variants: "method_call_removal" or
# "integer_literal:nil".
class OperatorYield::Selection
  attr_reader :specs

  def initialize(specs)
    @specs = specs.map { |spec| spec.split(":", 2) }
  end

  def to_s = specs.map { |op, var| var ? "#{op}:#{var}" : op }.join(",")

  def match?(operator, variant)
    specs.any? { |op, var| op == operator && (var.nil? || var == variant) }
  end

  # Whether dropping the selection takes the mutant out of the run. When a
  # kept operator generates the same mutated file, the planner reports the
  # mutant under that operator instead: it stays, with its verdict.
  def removes?(mutant)
    match?(mutant.operator, mutant.variant) && mutant.alternatives.all? { |op, var| match?(op, var) }
  end

  def returns?(mutant) = match?(mutant.operator, mutant.variant) && !removes?(mutant)
end
