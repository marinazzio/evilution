# frozen_string_literal: true

require_relative "../timeout_policy"

class Evilution::Runner::MutationExecutor::TimeoutPolicy::Base
  # Seconds the pool waits on any one of these mutations before it gives the
  # worker up; nil when they run without a limit.
  def item_timeout(mutations)
    longest = mutations.map { |mutation| call(mutation) }.max
    longest && (longest * Evilution::Runner::MutationExecutor::TimeoutPolicy::ITEM_TIMEOUT_FACTOR)
  end
end
