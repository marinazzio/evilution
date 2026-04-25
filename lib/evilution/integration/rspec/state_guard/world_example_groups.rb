# frozen_string_literal: true

require_relative "../../rspec"
require_relative "internals"

class Evilution::Integration::RSpec::StateGuard::WorldExampleGroups
  def snapshot
    groups = Evilution::Integration::RSpec::StateGuard::Internals.world_ivar(:@example_groups)
    groups ? groups.dup.freeze : nil
  end

  def release(before)
    return unless before

    groups = Evilution::Integration::RSpec::StateGuard::Internals.world_ivar(:@example_groups)
    return unless groups

    groups.select! { |g| before.include?(g) }
  end
end
