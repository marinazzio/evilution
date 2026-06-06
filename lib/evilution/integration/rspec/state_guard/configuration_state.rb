# frozen_string_literal: true

require_relative "../../rspec"

# Restores the RSpec.configuration state that ::RSpec::Core::Runner.run mutates
# on the shared singleton during an in-process mutation run (EV-dwqw / GH #1343).
#
# The visible symptom was every SUBSEQUENT host example rendering its progress
# dots without color (white instead of green). Root cause: the run's args carry
# "--no-color", and ConfigurationOptions#configure applies it via
# Configuration#force, which does `@preferred_options.merge!(:color_mode => :off)`
# IN PLACE. `Configuration#color_mode` reads `@preferred_options.fetch(:color_mode)`
# first, so the host's color setting stays :off for the rest of the process.
# Separately, Runner#setup points `output_stream`/`error_stream` (attr_writers,
# i.e. the @output_stream/@error_stream ivars) at the run's throwaway StringIOs.
#
# Forked runs never leak these (the mutation happens in a child that dies); only
# the in-process isolation path mutates the host's own configuration.
#
# @preferred_options is mutated in place, so it is snapshotted by DUP and put
# back by replacing the ivar; the stream ivars are reassigned during the run,
# so capturing the original references is enough.
class Evilution::Integration::RSpec::StateGuard::ConfigurationState
  PREFERRED_OPTIONS = :@preferred_options
  STREAM_IVARS = %i[@output_stream @error_stream].freeze
  ALL_IVARS = [PREFERRED_OPTIONS, *STREAM_IVARS].freeze

  # configuration is injectable for isolated unit testing; production uses the
  # shared RSpec.configuration singleton.
  def initialize(configuration: nil)
    @configuration = configuration
  end

  def snapshot
    config = configuration
    state = {}
    capture_preferred_options(config, state)
    STREAM_IVARS.each do |ivar|
      state[ivar] = config.instance_variable_get(ivar) if config.instance_variable_defined?(ivar)
    end
    state
  end

  # Restore exactly the pre-run state: ivars present at snapshot get their value
  # back; ivars created by the run but absent before are removed, so nothing the
  # run introduced can leak into the host either.
  def release(captured)
    return unless captured

    config = configuration
    ALL_IVARS.each do |ivar|
      if captured.key?(ivar)
        config.instance_variable_set(ivar, captured[ivar])
      elsif config.instance_variable_defined?(ivar)
        config.remove_instance_variable(ivar)
      end
    end
  end

  private

  def configuration
    @configuration || ::RSpec.configuration
  end

  def capture_preferred_options(config, state)
    return unless config.instance_variable_defined?(PREFERRED_OPTIONS)

    value = config.instance_variable_get(PREFERRED_OPTIONS)
    state[PREFERRED_OPTIONS] = value.is_a?(Hash) ? value.dup : value
  end
end
