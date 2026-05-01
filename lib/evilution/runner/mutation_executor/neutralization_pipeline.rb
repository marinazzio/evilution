# frozen_string_literal: true

require_relative "../mutation_executor"

class Evilution::Runner::MutationExecutor::NeutralizationPipeline
  def initialize(neutralizers)
    @neutralizers = neutralizers
  end

  def call(result, **ctx)
    @neutralizers.reduce(result) do |acc, nz|
      ctx.empty? ? nz.call(acc) : nz.call(acc, **ctx)
    end
  end
end
