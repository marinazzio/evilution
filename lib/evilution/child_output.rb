# frozen_string_literal: true

require_relative "../evilution"

module Evilution::ChildOutput
  module_function

  class << self
    attr_accessor :log_dir
  end

  # Per-run truncation happens once in the parent (Runner#configure_child_output);
  # within a run, multiple forks reusing the same PID (pool worker recycle, per-mutation
  # forks) append so cross-fork output isn't lost.
  def redirect!
    return unless log_dir

    pid = Process.pid
    $stdout.reopen(File.join(log_dir, "#{pid}.out"), "a")
    $stderr.reopen(File.join(log_dir, "#{pid}.err"), "a")
    $stdout.sync = true
    $stderr.sync = true
  end
end
