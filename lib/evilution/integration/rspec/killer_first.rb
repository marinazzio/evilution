# frozen_string_literal: true

require_relative "../rspec"
require_relative "example_order"

# Whether a mutation's run asks RSpec for the killer-first order (see
# ExampleOrder), and that order put in place for the run.
#
# Order matters only to a run that stops at its first kill: one that goes
# through every example costs the same in any order. Without killers or
# baseline times there is nothing to order by, and the defined order stands.
class Evilution::Integration::RSpec::KillerFirst
  def initialize(stop_on_kill:, durations:)
    @stop_on_kill = stop_on_kill
    @order = Evilution::Integration::RSpec::ExampleOrder.new(durations: durations)
    @killers = []
  end

  # The ids of the examples to run first, the most telling first; kept until
  # the next call.
  def prioritize(test_ids)
    @killers = Array(test_ids)
    nil
  end

  def applies?
    @stop_on_kill && Evilution::Integration::RSpec::ExampleOrder.supported? && @order.informed?(@killers)
  end

  # RSpec applies `--order` only to the first run in a process that names
  # one: from then on the order counts as forced, and naming another changes
  # nothing. A process that has already run RSpec -- the canary, a run before
  # this one -- would keep the defined order. So the ordering is made the
  # global one directly, as well as registered under the name the run's
  # arguments give, which is what decides when this run is the first.
  #
  # Afterwards the global ordering is the defined one, as the `--order
  # defined` of every other evilution run leaves it.
  def during(ordered)
    return yield unless ordered

    registry = ::RSpec.configuration.ordering_registry
    registry.register(Evilution::Integration::RSpec::ExampleOrder::NAME, @order)
    registry.register(:global, @order)
    @order.start(@killers)
    yield
  ensure
    if ordered
      @order.finish
      registry.register(:global, registry.fetch(:defined))
    end
  end
end
