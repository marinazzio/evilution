# frozen_string_literal: true

require "spec_helper"
require "open3"
require "rbconfig"
require "evilution/coverage/load_tracker"

RSpec.describe Evilution::Coverage::LoadTracker do
  # Coverage is process-wide state, so each case runs in a Ruby of its own.
  def run_ruby(body)
    script = <<~RUBY
      require "coverage"
      require "evilution/coverage/load_tracker"
      #{body}
    RUBY
    lib_dir = File.expand_path("../../../lib", __dir__)
    out, err, status = Open3.capture3(RbConfig.ruby, "-I", lib_dir, "-e", script)
    raise "script failed: #{err}" unless status.success?

    out.lines.map(&:strip)
  end

  it "counts the lines a file runs while it loads, and pauses afterwards" do
    out = run_ruby(<<~RUBY)
      require "tmpdir"
      Dir.mktmpdir do |dir|
        path = File.join(dir, "loaded.rb")
        File.write(path, "X = 1\\n")
        tracker = Evilution::Coverage::LoadTracker.new
        tracker.start
        require path
        tracker.pause
        puts Coverage.state
        puts Coverage.peek_result[path][:lines].inspect
      end
    RUBY

    expect(out).to eq(["suspended", "[1]"])
  end

  it "leaves coverage that something else started alone" do
    out = run_ruby(<<~RUBY)
      Coverage.start(lines: true)
      tracker = Evilution::Coverage::LoadTracker.new
      tracker.start
      tracker.pause
      puts Coverage.state
    RUBY

    expect(out).to eq(["running"])
  end

  # The baseline and the mutation runs are forked from the process that paused
  # the counting. Coverage set up and paused cannot be started again
  # (`Coverage.start` raises once it is set up, and `running?` is false), so a
  # spec helper that starts coverage itself, as SimpleCov does, would fail there.
  describe ".release_inherited" do
    it "hands a forked child coverage it can start afresh, and keeps the parent's paused" do
      out = run_ruby(<<~RUBY)
        tracker = Evilution::Coverage::LoadTracker.new
        tracker.start
        tracker.pause
        read, write = IO.pipe
        pid = fork do
          read.close
          Evilution::Coverage::LoadTracker.release_inherited
          Coverage.start(lines: true) unless Coverage.running?
          write.puts(Coverage.state)
          write.close
          exit!(0)
        end
        write.close
        Process.wait(pid)
        puts read.read
        puts Coverage.state
      RUBY

      expect(out).to eq(%w[running suspended])
    end

    it "leaves coverage that something else started alone" do
      out = run_ruby(<<~RUBY)
        Coverage.setup(lines: true)
        Evilution::Coverage::LoadTracker.release_inherited
        puts Coverage.state
        Coverage.resume
        Coverage.suspend
        Evilution::Coverage::LoadTracker.release_inherited
        puts Coverage.state
      RUBY

      expect(out).to eq(%w[suspended suspended])
    end

    it "leaves coverage the preload started while the tracker counted alone once it runs" do
      out = run_ruby(<<~RUBY)
        tracker = Evilution::Coverage::LoadTracker.new
        tracker.start
        tracker.pause
        Coverage.resume
        Evilution::Coverage::LoadTracker.release_inherited
        puts Coverage.state
      RUBY

      expect(out).to eq(["running"])
    end
  end

  it "pauses nothing it did not start" do
    out = run_ruby(<<~RUBY)
      Evilution::Coverage::LoadTracker.new.pause
      puts Coverage.state
    RUBY

    expect(out).to eq(["idle"])
  end
end
