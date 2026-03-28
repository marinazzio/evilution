# frozen_string_literal: true

require_relative "heuristic/noop_source"
require_relative "heuristic/method_body_nil"
require_relative "heuristic/alias_swap"
require_relative "heuristic/dead_code"
require_relative "heuristic/frozen_string"
require_relative "heuristic/redundant_boolean_return"
require_relative "heuristic/arithmetic_identity"

require_relative "../equivalent"

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
      Evilution::Equivalent::Heuristic::NoopSource.new,
      Evilution::Equivalent::Heuristic::MethodBodyNil.new,
      Evilution::Equivalent::Heuristic::AliasSwap.new,
      Evilution::Equivalent::Heuristic::DeadCode.new,
      Evilution::Equivalent::Heuristic::FrozenString.new,
      Evilution::Equivalent::Heuristic::RedundantBooleanReturn.new,
      Evilution::Equivalent::Heuristic::ArithmeticIdentity.new
    ]
  end
end
