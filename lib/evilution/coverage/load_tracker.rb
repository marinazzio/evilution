# frozen_string_literal: true

require "coverage"
require_relative "../coverage"

# Counts lines from before the project is preloaded until it has been. Ruby
# counts only the files loaded after counting is set up, so without this a
# preloaded file is missing from the coverage map altogether -- and the map
# needs to know what ran while the files loaded (a class body, a `def`, a
# constant) to tell a line no example executes from one that runs only at load.
#
# Paused afterwards: the coverage map's build resumes it in a child of its own
# (Evilution::Coverage::MapBuilder). Every other child forked from this process
# runs tests and must not inherit it paused: set up, coverage cannot be started
# again, so a spec helper that starts it (as SimpleCov does) would raise there.
# Those children call .release_inherited first.
class Evilution::Coverage::LoadTracker
  @paused = false

  class << self
    # In a forked child that runs tests: stops the counting a tracker paused
    # in the process it was forked from, so the tests find coverage as they
    # would without one. Coverage that anything else set up is left alone.
    def release_inherited
      return unless @paused && ::Coverage.state == :suspended

      ::Coverage.result(stop: true, clear: true)
      @paused = false
    end

    def paused!
      @paused = true
    end
  end

  def start
    return unless ::Coverage.state == :idle

    ::Coverage.setup(lines: true)
    ::Coverage.resume
    @started = true
  end

  def pause
    return unless @started && ::Coverage.state == :running

    ::Coverage.suspend
    self.class.paused!
  end
end
