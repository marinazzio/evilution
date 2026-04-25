# frozen_string_literal: true

require_relative "../../rspec"
require_relative "internals"

class Evilution::Integration::RSpec::StateGuard::WorldFilteredExamples
  def snapshot
    fe = Evilution::Integration::RSpec::StateGuard::Internals.world_ivar(:@filtered_examples)
    fe ? Set.new(fe.keys.map(&:object_id)) : nil
  end

  def release(snapshot_keys)
    fe = Evilution::Integration::RSpec::StateGuard::Internals.world_ivar(:@filtered_examples)
    return unless fe && snapshot_keys

    fe.each_key.to_a.each do |k|
      fe.delete(k) unless snapshot_keys.include?(k.object_id)
    end
  end
end
