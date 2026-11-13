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
  def self.default
    @default ||= new
  end

  # The modules extended with `concern`, the ActiveSupport::Concern module of
  # the process. A different module than the one asked about last (a project
  # whose ActiveSupport was loaded again) starts the record over.
  def concerns(concern)
    track(concern) unless concern.equal?(@concern)
    @modules.keys
  end

  # Called by the hook in `concern`'s `extended`. Nothing is recorded before
  # the first #concerns: the walk made then finds what was extended until it.
  def record(concern, base)
    @modules[base] = true if concern.equal?(@concern)
  end

  private

  def track(concern)
    @concern = concern
    @modules = ObjectSpace::WeakMap.new
    concern.singleton_class.prepend(hook)
    ObjectSpace.each_object(Module) { |mod| @modules[mod] = true if concern === mod } # rubocop:disable Style/CaseEquality
  end

  def hook
    @hook ||= build_hook
  end

  def build_hook
    registry = self
    Module.new do
      define_method(:extended) do |base|
        registry.record(self, base)
        super(base)
      end
    end
  end
end
