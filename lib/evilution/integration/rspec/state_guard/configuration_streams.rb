# frozen_string_literal: true

require_relative "../../rspec"
require_relative "internals"

# Restores the RSpec.configuration fields that ::RSpec::Core::Runner.run mutates
# on the shared singleton during an in-process mutation run (EV-dwqw / GH #1343):
#
#   - @color_mode    -- the run's args carry "--no-color", flipping it to :off,
#                       which makes every SUBSEQUENT host example render its
#                       progress dots without color (white instead of green).
#   - @output_stream -- Runner#setup swaps it to the run's StringIO whenever the
#                       host's was $stdout.
#   - @error_stream  -- likewise pointed at the run's StringIO.
#
# Forked runs never leak these (the mutation happens in a child that dies), but
# the in-process isolation path mutates the host's own configuration. Restore by
# writing the ivars directly: configuration#output_stream= is guarded (it warns
# and no-ops once a reporter exists), so the public setter cannot put it back.
class Evilution::Integration::RSpec::StateGuard::ConfigurationStreams
  IVARS = %i[@color_mode @output_stream @error_stream].freeze

  def snapshot
    config = ::RSpec.configuration
    IVARS.each_with_object({}) do |ivar, acc|
      acc[ivar] = config.instance_variable_get(ivar) if config.instance_variable_defined?(ivar)
    end
  end

  # Restore exactly the pre-run state: ivars present at snapshot get their value
  # back; ivars that were absent before but created by the run are removed, so a
  # newly-defined ivar can't leak into the host either.
  def release(captured)
    return unless captured

    config = ::RSpec.configuration
    IVARS.each do |ivar|
      if captured.key?(ivar)
        config.instance_variable_set(ivar, captured[ivar])
      elsif config.instance_variable_defined?(ivar)
        config.remove_instance_variable(ivar)
      end
    end
  end
end
