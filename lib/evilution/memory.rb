# frozen_string_literal: true

module Evilution::Memory
  PROC_STATUS_PATH = "/proc/%d/status"
  RSS_PATTERN = /VmRSS:\s+(\d+)\s+kB/

  module_function

  def rss_kb
    rss_kb_for(Process.pid)
  end

  def rss_mb
    kb = rss_kb
    return nil unless kb

    kb / 1024.0
  end

  def rss_kb_for(pid)
    path = format(PROC_STATUS_PATH, pid)
    content = File.read(path)
    match = content.match(RSS_PATTERN)
    return nil unless match

    match[1].to_i
  rescue Errno::ENOENT, Errno::EACCES, Errno::ESRCH
    nil
  end

  def delta
    before = rss_kb
    result = yield
    after = rss_kb
    delta_kb = before && after ? after - before : nil
    [result, delta_kb]
  end
end
