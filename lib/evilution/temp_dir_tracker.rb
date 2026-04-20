# frozen_string_literal: true

require "fileutils"
require "monitor"
require_relative "version"

module Evilution::TempDirTracker
  @dirs = Set.new
  @monitor = Monitor.new
  @at_exit_registered = false

  def self.register(dir)
    @monitor.synchronize do
      @dirs << dir
      register_at_exit unless @at_exit_registered
    end
  end

  def self.unregister(dir)
    @monitor.synchronize { @dirs.delete(dir) }
  end

  def self.cleanup_all
    # Trap-safe: Signal.trap handlers forbid Monitor#synchronize, so both the
    # snapshot and the per-dir tracking removal fall back to a lock-free path
    # when ThreadError is raised. Successful removals drop the entry from
    # @dirs; failures stay tracked so a later cleanup can retry.
    snapshot_tracked_dirs.each do |d|
      FileUtils.rm_rf(d)
      remove_from_tracking(d)
    rescue StandardError
      nil
    end
  end

  def self.tracked_dirs
    @monitor.synchronize { @dirs.dup }
  end

  def self.register_at_exit
    at_exit { cleanup_all }
    @at_exit_registered = true
  end
  private_class_method :register_at_exit

  def self.snapshot_tracked_dirs
    @monitor.synchronize { @dirs.to_a }
  rescue ThreadError
    @dirs.to_a
  end
  private_class_method :snapshot_tracked_dirs

  def self.remove_from_tracking(dir)
    @monitor.synchronize { @dirs.delete(dir) }
  rescue ThreadError
    @dirs.delete(dir)
  end
  private_class_method :remove_from_tracking
end
