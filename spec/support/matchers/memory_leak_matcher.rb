# frozen_string_literal: true

RSpec::Matchers.define :leak_memory do
  chain :over do |iterations|
    @iterations = iterations
  end

  chain :by_more_than do |max_growth_kb|
    @max_growth_kb = max_growth_kb
  end

  match do |block|
    @iterations ||= 20
    @max_growth_kb ||= 10_240 # 10 MB

    GC.start
    GC.compact if GC.respond_to?(:compact)
    rss_before = Evilution::Memory.rss_kb

    @iterations.times { block.call }

    GC.start
    GC.compact if GC.respond_to?(:compact)
    rss_after = Evilution::Memory.rss_kb

    return false unless rss_before && rss_after

    @actual_growth_kb = rss_after - rss_before
    @actual_growth_kb > @max_growth_kb
  end

  failure_message do
    "expected memory growth to exceed #{format_mb(@max_growth_kb)}, " \
      "but grew by #{format_mb(@actual_growth_kb)}"
  end

  failure_message_when_negated do
    "expected memory growth not to exceed #{format_mb(@max_growth_kb)}, " \
      "but grew by #{format_mb(@actual_growth_kb)}"
  end

  def format_mb(kb)
    format("%.1f MB", kb / 1024.0)
  end

  supports_block_expectations
end
