# frozen_string_literal: true

require_relative "../rspec"
require_relative "state_guard/object_space_example_groups"
require_relative "state_guard/world_example_groups"
require_relative "state_guard/world_sources_by_path"
require_relative "state_guard/world_filtered_examples"
require_relative "state_guard/reporter_arrays"
require_relative "state_guard/example_groups_constants"

class Evilution::Integration::RSpec::StateGuard
  DEFAULT_STRATEGIES = [
    ObjectSpaceExampleGroups.new,
    WorldExampleGroups.new,
    WorldSourcesByPath.new,
    WorldFilteredExamples.new,
    ReporterArrays.new,
    ExampleGroupsConstants.new
  ].freeze

  def initialize(strategies: DEFAULT_STRATEGIES)
    @strategies = strategies
  end

  def snapshot
    @strategies.map { |s| [s, s.snapshot] }
  end

  def release(token)
    token.reverse_each { |strategy, captured| release_one(strategy, captured) }
  end

  private

  def release_one(strategy, captured)
    strategy.release(captured)
  rescue StandardError => e
    warn "[evilution] state release failed for #{strategy.class.name}: #{e.class}: #{e.message}"
  end
end
