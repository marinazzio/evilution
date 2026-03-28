# frozen_string_literal: true

require_relative "heuristic/noop_source"
require_relative "heuristic/method_body_nil"
require_relative "heuristic/alias_swap"
require_relative "heuristic/dead_code"

class Evilution::Equivalent::Detector
  def initialize(heuristics: nil)
    @heuristics = heuristics || default_heuristics
  end

  def call(mutations)
    equivalent = []
    remaining = []

    mutations.each do |mutation|
      if @heuristics.any? { |h| h.match?(mutation) }
        equivalent << mutation
      else
        remaining << mutation
      end
    end

    [equivalent, remaining]
  end

  private

  def default_heuristics
    [
      Heuristic::NoopSource.new,
      Heuristic::MethodBodyNil.new,
      Heuristic::AliasSwap.new,
      Heuristic::DeadCode.new
    ]
  end
end
