# frozen_string_literal: true

require_relative "../loading"

# Remembers which test classes each test file registered when it was loaded,
# so a process that runs many mutations loads a test file once.
#
# Minitest and Test::Unit learn of a test class when it is first defined.
# Loading its file again reopens the class and registers nothing, so the
# second mutation run in a process would find no tests. The classes of the
# first load are handed back instead.
#
# The block given to .new returns the classes registered so far; what a load
# adds to them is taken to be that file's.
class Evilution::Integration::Loading::TestClassCache
  def initialize(&registered)
    @registered = registered
    @classes = {}
    @partial = {}
  end

  # The classes the given files registered. Yields each file that has not
  # been loaded yet; the block loads it.
  def fetch(files, &)
    files.flat_map { |file| @classes[file] ||= load_once(file, &) }.uniq
  end

  def clear
    @classes.clear
    @partial.clear
  end

  private

  # A load that raises is tried again next time. Classes it defined before
  # raising are already registered and will not register again, so they are
  # kept for that next attempt.
  def load_once(file)
    before = @registered.call
    yield file
    @partial.fetch(file, []) | (@registered.call - before)
  rescue ScriptError, StandardError
    @partial[file] = @partial.fetch(file, []) | (@registered.call - before)
    raise
  end
end
