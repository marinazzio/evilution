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

  it "pauses nothing it did not start" do
    out = run_ruby(<<~RUBY)
      Evilution::Coverage::LoadTracker.new.pause
      puts Coverage.state
    RUBY

    expect(out).to eq(["idle"])
  end
end
