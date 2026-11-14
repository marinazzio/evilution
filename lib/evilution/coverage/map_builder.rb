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
    @prior_counts = counted_so_far
    Evilution::Coverage::Map.from_h(build_in_fork)
  end

  private

  def build_in_fork
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
    Marshal.load(payload)
  end

  # Runs entirely inside the forked child.
  def build_in_child
    recorder = Evilution::Coverage::Recorder.new(target_files: @target_files, prior_counts: @prior_counts)
    unvouched = loaded_uncounted
    count_lines
    # The child inherited the parent's fully-loaded RSpec.world; wipe it so the
    # nested runner executes ONLY @spec_files and never re-enters the host suite
    # (which would recursively fork this builder).
    reset_world
    install_hook(recorder)
    ::RSpec::Core::Runner.run(@spec_files, StringIO.new, StringIO.new)
    vouched = run_complete? ? @target_files - unvouched : []
    recorder.to_map(built_files: @target_files, vouched_files: vouched, spec_files: @spec_files)
  end

  # The parent may have started counting before its preload and paused it
  # since (Evilution::Coverage::LoadTracker). Read in the parent: a forked
  # child starts its counts from zero.
  def counted_so_far
    ::Coverage.state == :idle ? {} : ::Coverage.peek_result
  end

  def count_lines
    case ::Coverage.state
    when :suspended then ::Coverage.resume
    when :idle then ::Coverage.start(lines: true)
    end
  end

  # Target files already loaded with every line at zero: they loaded while
  # nothing was counting, so the lines that ran as they loaded (a class body,
  # a `def`, a constant) read as never run. No line of theirs can be vouched for.
  def loaded_uncounted
    @target_files.select do |file|
      lines = line_counts(@prior_counts[file])
      lines && lines.none? { |count| count.is_a?(Integer) && count.positive? }
    end
  end

  def line_counts(entry)
    entry.is_a?(Hash) ? entry[:lines] : entry
  end

  # Whether every example of the spec files ran: a spec file that failed to
  # load runs none, a run that stopped early (fail-fast, an interrupt) fewer
  # than it loaded, and either leaves lines at zero that a full run executes.
  def run_complete?
    loaded = ::RSpec.world.example_count
    loaded.positive? && ::RSpec.configuration.reporter.examples.length == loaded
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
