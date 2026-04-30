# frozen_string_literal: true

require_relative "version"

module Evilution::ProcessCleanup
  module_function

  def safe_kill(signal, pid)
    ::Process.kill(signal, pid)
  rescue Errno::ESRCH
    nil
  end

  def safe_wait(pid)
    ::Process.wait(pid)
  rescue Errno::ECHILD
    nil
  end
end
