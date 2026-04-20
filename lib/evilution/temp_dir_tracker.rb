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
    # Trap-safe: Signal.trap handlers forbid Monitor#synchronize, so we
    # snapshot and iterate without the mutex. The trade-off is a best-effort
    # guarantee against concurrent register/unregister during shutdown.
    dirs = @dirs.to_a
    dirs.each do |d|
      FileUtils.rm_rf(d)
    rescue StandardError
      nil
    end
    @dirs.clear
  end

  def self.tracked_dirs
    @monitor.synchronize { @dirs.dup }
  end

  def self.register_at_exit
    at_exit { cleanup_all }
    @at_exit_registered = true
  end
  private_class_method :register_at_exit
end
