# frozen_string_literal: true

require "fileutils"

require_relative "../evilution"

module Evilution::TempDirTracker
  @dirs = Set.new
  @mutex = Mutex.new
  @at_exit_registered = false

  def self.register(dir)
    @mutex.synchronize do
      @dirs << dir
      register_at_exit unless @at_exit_registered
    end
  end

  def self.unregister(dir)
    @mutex.synchronize { @dirs.delete(dir) }
  end

  def self.cleanup_all
    @mutex.synchronize do
      @dirs.each { |d| FileUtils.rm_rf(d) }
      @dirs.clear
    end
  end

  def self.tracked_dirs
    @mutex.synchronize { @dirs.dup }
  end

  def self.register_at_exit
    at_exit { cleanup_all }
    @at_exit_registered = true
  end
  private_class_method :register_at_exit
end
