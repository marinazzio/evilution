# frozen_string_literal: true

require_relative "../timeout_policy"

class Evilution::Runner::MutationExecutor::TimeoutPolicy::Base
  # The limit a timeout under #call is confirmed under before it is reported,
  # by running the mutation again; nil when a timeout under #call stands.
  def confirmation_limit(_mutation)
    nil
  end

  # The limit a timeout this mutation reports has used up: the longest its
  # test run is allowed.
  def final_limit(mutation)
    confirmation_limit(mutation) || call(mutation)
  end

  # Seconds the pool waits on any one of these mutations before it gives the
  # worker up: a multiple of the longest one of them may take, a timed-out run
  # and its confirmation together; nil when they run without a limit.
  def item_timeout(mutations)
    longest = mutations.map { |mutation| longest_run(mutation) }
    return nil if longest.empty? || longest.include?(nil)

    longest.max * Evilution::Runner::MutationExecutor::TimeoutPolicy::ITEM_TIMEOUT_FACTOR
  end

  private

  def longest_run(mutation)
    limit = call(mutation)
    confirmation = confirmation_limit(mutation)
    confirmation ? limit + confirmation : limit
  end
end
