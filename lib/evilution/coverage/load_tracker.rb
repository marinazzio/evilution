# frozen_string_literal: true

require "coverage"
require_relative "../coverage"

# Counts lines from before the project is preloaded until it has been. Ruby
# counts only the files loaded after counting is set up, so without this a
# preloaded file is missing from the coverage map altogether -- and the map
# needs to know what ran while the files loaded (a class body, a `def`, a
# constant) to tell a line no example executes from one that runs only at load.
#
# Paused afterwards: the baseline and the mutation runs are forked from this
# process, and none of them needs the counting. The coverage map's build
# resumes it in a child of its own (Evilution::Coverage::MapBuilder).
class Evilution::Coverage::LoadTracker
  def start
    return unless ::Coverage.state == :idle

    ::Coverage.setup(lines: true)
    ::Coverage.resume
    @started = true
  end

  def pause
    return unless @started && ::Coverage.state == :running

    ::Coverage.suspend
  end
end
