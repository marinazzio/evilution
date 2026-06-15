# frozen_string_literal: true

require "coverage"
require "stringio"
require_relative "../coverage"
require_relative "map"
require_relative "recorder"

# Builds a per-example coverage Map by running the given spec files under
# ::Coverage (lines mode) with the Recorder installed as an around(:each)
# hook. The run happens in a FORKED CHILD so the global ::RSpec.configure
# hook, ::RSpec.world mutation, and ::Coverage state never leak into the
# calling process; the parent receives only the serialized map over a pipe.
class Evilution::Coverage::MapBuilder
  LOCATION_LINE_SUFFIX = /\A(.+?)(:\d+(?::\d+)*)\z/

  # RSpec reports example locations relative to its run dir as "./spec/x.rb:5".
  # Store them ABSOLUTE (path expanded against the project root, line suffix
  # preserved) so they replay regardless of the per-mutation run's CWD --
  # Integration::RSpec#resolve_target passes absolute targets through unchanged.
  def self.absolute_location(raw, root)
    match = LOCATION_LINE_SUFFIX.match(raw)
    path, suffix = match ? [match[1], match[2]] : [raw, ""]
    "#{File.expand_path(path, root)}#{suffix}"
  end

  def initialize(spec_files:, target_files:, project_root: Evilution::PROJECT_ROOT)
    @spec_files = spec_files
    @target_files = target_files
    @project_root = project_root.to_s
  end

  def call
    read_io, write_io = IO.pipe
    read_io.binmode
    write_io.binmode
    pid = fork do
      read_io.close
      Marshal.dump(build_in_child.to_h, write_io)
      write_io.close
      exit!(0)
    end
    write_io.close
    payload = read_io.read
    read_io.close
    Process.wait(pid)
    # Trust boundary: payload is a Marshal dump this process's own forked child
    # produced over a private pipe -- same rationale as Channel::Frame.
    Evilution::Coverage::Map.from_h(Marshal.load(payload))
  end

  private

  # Runs entirely inside the forked child.
  def build_in_child
    recorder = Evilution::Coverage::Recorder.new(target_files: @target_files)
    ::Coverage.start(lines: true) unless ::Coverage.running?
    # The child inherited the parent's fully-loaded RSpec.world; wipe it so the
    # nested runner executes ONLY @spec_files and never re-enters the host suite
    # (which would recursively fork this builder).
    reset_world
    install_hook(recorder)
    ::RSpec::Core::Runner.run(@spec_files, StringIO.new, StringIO.new)
    recorder.to_map(built_files: @target_files)
  end

  def reset_world
    ::RSpec.respond_to?(:clear_examples) ? ::RSpec.clear_examples : ::RSpec.reset
  end

  def install_hook(recorder)
    root = @project_root
    ::RSpec.configure do |config|
      config.around(:each) do |example|
        location = Evilution::Coverage::MapBuilder.absolute_location(
          example.metadata[:location].to_s, root
        )
        recorder.around_example(location) { example.run }
      end
    end
  end
end
