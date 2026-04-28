# frozen_string_literal: true

require_relative "../result"

class Evilution::Result::MemoryStats
  attr_reader :child_rss_kb, :memory_delta_kb, :parent_rss_kb

  def self.from_fields(child_rss_kb: nil, memory_delta_kb: nil, parent_rss_kb: nil)
    return nil if child_rss_kb.nil? && memory_delta_kb.nil? && parent_rss_kb.nil?

    new(child_rss_kb: child_rss_kb, memory_delta_kb: memory_delta_kb, parent_rss_kb: parent_rss_kb)
  end

  def initialize(child_rss_kb: nil, memory_delta_kb: nil, parent_rss_kb: nil)
    @child_rss_kb = child_rss_kb
    @memory_delta_kb = memory_delta_kb
    @parent_rss_kb = parent_rss_kb
    freeze
  end
end
