# frozen_string_literal: true

require "fileutils"

require_relative "../evilution"

module Evilution::ChildOutput
  module_function

  class << self
    attr_accessor :log_dir
  end

  def redirect!
    return unless log_dir

    FileUtils.mkdir_p(log_dir)
    pid = Process.pid
    $stdout.reopen(File.join(log_dir, "#{pid}.out"), "a")
    $stderr.reopen(File.join(log_dir, "#{pid}.err"), "a")
    $stdout.sync = true
    $stderr.sync = true
  end
end
