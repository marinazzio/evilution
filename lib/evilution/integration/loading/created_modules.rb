# frozen_string_literal: true

require_relative "../loading"

# Sees the modules created while a block runs, as they are created.
#
# SupersededModules needs the modules an evaluation of a file created. Taking
# them as the difference between two walks of ObjectSpace, before and after,
# visited every object in the process twice per evaluation, and an in-process
# run evaluates every file twice per mutation (the mutation, then the
# restore). Here Module#initialize is hooked instead, once for the process,
# when the first block is run: `Module.new` passes through it, with or
# without a body. Nothing is recorded while no block runs.
#
# Every module whose initialize runs is added, whatever its class, and
# whether or not its body raised; telling them apart is the caller's
# business. A module created in another thread while the block runs is added
# too, as the walk would have found it.
module Evilution::Integration::Loading::CreatedModules
  @lists = [].freeze

  # Runs the block, adding to `list` each module created while it runs;
  # returns the block's value.
  def self.into(list)
    # Prepending a module Module already has is a no-op.
    ::Module.prepend(Hook)
    @lists = [*@lists, list].freeze
    yield
  ensure
    @lists = @lists.reject { |open| open.equal?(list) }.freeze
  end

  def self.record(mod)
    @lists.each { |list| list << mod }
  end

  module Hook
    private

    # Recorded before the body runs, so that a module whose body raises is
    # recorded all the same.
    def initialize(*, **, &)
      Evilution::Integration::Loading::CreatedModules.record(self)
      super
    end
  end
end
