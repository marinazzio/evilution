# frozen_string_literal: true

require_relative "../../rspec"
require_relative "internals"

class Evilution::Integration::RSpec::StateGuard::WorldSourcesByPath
  def snapshot
    src = Evilution::Integration::RSpec::StateGuard::Internals.world_ivar(:@sources_by_path)
    src ? Set.new(src.keys) : nil
  end

  def release(before)
    return unless before

    src = Evilution::Integration::RSpec::StateGuard::Internals.world_ivar(:@sources_by_path)
    return unless src

    src.delete_if { |k, _v| !before.include?(k) }
  end
end
