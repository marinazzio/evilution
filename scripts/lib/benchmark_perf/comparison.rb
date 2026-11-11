# frozen_string_literal: true

require_relative "version_sample"

module BenchmarkPerf
  OperatorRow = Struct.new(:operator, :state, :base_count, :other_count, :base_duration, :other_duration,
                           :count_effect, :cost_effect, keyword_init: true)

  # Splits a total change into "more units" and "each unit costs more":
  #   new_total - old_total = (n_new - n_old) * c_old + n_new * (c_new - c_old)
  # with c = total / n. Undefined (nil) when either count is zero.
  module Decomposition
    module_function

    def call(base_count, base_total, other_count, other_total)
      return [nil, nil] if base_count.zero? || other_count.zero?

      base_cost = base_total / base_count
      other_cost = other_total / other_count
      [(other_count - base_count) * base_cost, other_count * (other_cost - base_cost)]
    end
  end

  # Baseline vs one other version on one target.
  class Comparison
    def initialize(base:, other:)
      @base = base
      @other = other
    end

    def available?
      !@base.failed? && !@other.failed?
    end

    def delta_wall
      return nil unless available?

      @other.wall_median - @base.wall_median
    end

    def base_wall
      available? ? @base.wall_median : nil
    end

    def count_effect
      wall_split.first
    end

    def cost_effect
      wall_split.last
    end

    def noise?
      return false unless available?

      spread = (@base.wall_max - @base.wall_min) + (@other.wall_max - @other.wall_min)
      delta_wall.abs < spread
    end

    def common_count
      common_keys.size
    end

    def lost_kills
      killed_in_base.reject { |key| %w[killed timeout].include?(@other.statuses[key]) }.sort
    end

    def flips_to_timeout
      killed_in_base.select { |key| @other.statuses[key] == "timeout" }.sort
    end

    def operator_rows
      return [] unless available?

      names = (@base.operators.keys | @other.operators.keys)
      names.map { |name| operator_row(name) }
           .sort_by { |row| -(row.other_duration - row.base_duration).abs }
    end

    private

    def wall_split
      return [nil, nil] unless available?

      Decomposition.call(@base.mutant_count, @base.wall_median, @other.mutant_count, @other.wall_median)
    end

    def common_keys
      return [] unless available?

      @base.statuses.keys & @other.statuses.keys
    end

    def killed_in_base
      common_keys.select { |key| @base.statuses[key] == "killed" }
    end

    def operator_row(name)
      base = @base.operators.fetch(name, { count: 0, duration: 0.0 })
      other = @other.operators.fetch(name, { count: 0, duration: 0.0 })
      count_effect, cost_effect = Decomposition.call(base[:count], base[:duration], other[:count], other[:duration])
      OperatorRow.new(operator: name, state: operator_state(name),
                      base_count: base[:count], other_count: other[:count],
                      base_duration: base[:duration], other_duration: other[:duration],
                      count_effect: count_effect, cost_effect: cost_effect)
    end

    def operator_state(name)
      return :added unless @base.operators.key?(name)
      return :removed unless @other.operators.key?(name)

      :both
    end
  end
end
