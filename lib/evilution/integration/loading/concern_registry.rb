# frozen_string_literal: true

require_relative "../loading"

# The modules extended with ActiveSupport::Concern, for ConcernStateCleaner to
# look through before every evaluation of a mutated or restored file.
#
# Finding them by walking ObjectSpace on every evaluation visited every object
# in the process. Here the heap is walked once, the first time the registry is
# asked, for the concerns that already exist; the ones defined afterwards are
# recorded as they extend themselves, through a hook on the concern module's
# own `extended`. The registry is shared by the process, so a run that asks
# once in the parent (see ConcernStateCleaner#warm) leaves every forked
# mutation process a filled copy and no walk to make.
#
# The hook is one module for every registry, prepended at most once: a
# prepended module cannot be taken off, so one per registry would stay on the
# concern module for the life of the process, each run by every `extend`.
#
# Only modules that extend themselves with the concern module are recorded
# after the walk. A module extended with another module that includes it, or
# a `clone` of a concern, answers `concern === mod` without passing through
# `extended`, and is not listed. Neither can be given an `included` block of
# its own by a file that loads: the first is never set up to be included
# (ActiveSupport leaves its dependencies unset), and the second already holds
# the block of the concern it was cloned from.
#
# A module that is no longer referenced is not kept alive by being listed:
# a mutation that re-creates a concern leaves the old module to the garbage
# collector.
#
# No message is sent to the modules walked or recorded. ObjectSpace yields
# modules that answer messages in their own way, such as ActiveSupport's
# DeprecatedConstantProxy, which turns any of them into a deprecation that a
# project may have set to raise. `concern === mod` is answered by the concern
# module, and the record is keyed by identity.
class Evilution::Integration::Loading::ConcernRegistry
  # The registries that have tracked a concern module; weakly held, so that
  # one dropped by its owner is not kept alive by the hook.
  @tracking = ObjectSpace::WeakMap.new

  def self.default
    @default ||= new
  end

  # Called by the hook in a concern module's `extended`.
  def self.extended_with(concern, base)
    @tracking.each_key { |registry| registry.record(concern, base) }
  end

  def self.track(registry, concern)
    @tracking[registry] = true
    # Prepending a module the singleton class already has is a no-op.
    concern.singleton_class.prepend(Hook)
  end

  module Hook
    def extended(base)
      Evilution::Integration::Loading::ConcernRegistry.extended_with(self, base)
      super
    end
  end

  # The modules extended with `concern`, the ActiveSupport::Concern module of
  # the process. A different module than the one asked about last (a project
  # whose ActiveSupport was loaded again) starts the record over.
  def concerns(concern)
    track(concern) unless concern.equal?(@concern)
    @modules.keys
  end

  # Called for every registry when a module extends itself with `concern`,
  # whichever concern module the registry tracks. Nothing is recorded before
  # the first #concerns: the walk made then finds what was extended until it.
  def record(concern, base)
    @modules[base] = true if concern.equal?(@concern)
  end

  private

  def track(concern)
    @concern = concern
    @modules = ObjectSpace::WeakMap.new
    self.class.track(self, concern)
    ObjectSpace.each_object(Module) { |mod| @modules[mod] = true if concern === mod } # rubocop:disable Style/CaseEquality
  end
end
