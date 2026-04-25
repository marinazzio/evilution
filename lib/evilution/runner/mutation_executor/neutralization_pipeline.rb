# frozen_string_literal: true

class Evilution::Runner; end unless defined?(Evilution::Runner) # rubocop:disable Lint/EmptyClass
class Evilution::Runner::MutationExecutor; end unless defined?(Evilution::Runner::MutationExecutor) # rubocop:disable Lint/EmptyClass

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
