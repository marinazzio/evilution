# frozen_string_literal: true

require_relative "../parallel"

# The mutations of a parallel run as the pool sends them out: each paired
# with the tests that killed its neighbours (see KillHistory), looked up when
# the pool takes it, not when the run began, so it carries every kill reported
# by then.
class Evilution::Runner::MutationExecutor::Strategy::Parallel::HintedItems
  def initialize(mutations, kill_history)
    @mutations = mutations
    @kill_history = kill_history
  end

  def length
    @mutations.length
  end

  def empty?
    @mutations.empty?
  end

  def [](index)
    mutation = @mutations[index]
    [mutation, @kill_history.killers_for(mutation)]
  end
end
