# frozen_string_literal: true

require_relative "drop_cost"

# The drop costs of one selection over several targets, added up.
class OperatorYield::CostSum
  def self.of(targets, selection)
    new(targets.values.map { |ms| OperatorYield::DropCost.new(ms, selection) })
  end

  def initialize(costs)
    @costs = costs
  end

  def removed = @costs.flat_map(&:removed)

  %i[removed_count returned time kills survivors lost_kills survivor_lines_lost].each do |name|
    define_method(name) { @costs.sum(&name) }
  end
end
