# frozen_string_literal: true

require_relative "memory_growth_probe"

# Growth over @iterations runs of the block, read once the block has stopped
# warming up (see MemoryGrowthProbe). A round counts as settled when it grows
# the process by no more than a quarter of the allowed growth.
RSpec::Matchers.define :leak_memory do
  settled_fraction = 4

  chain :over do |iterations|
    @iterations = iterations
  end

  chain :by_more_than do |max_growth_kb|
    @max_growth_kb = max_growth_kb
  end

  match do |block|
    @iterations ||= 20
    @max_growth_kb ||= 10_240 # 10 MB

    skip "RSS measurement unavailable" unless Evilution::Memory.rss_kb

    probe = MemoryGrowthProbe.new(iterations: @iterations, settled_below_kb: @max_growth_kb / settled_fraction)
    @actual_growth_kb = probe.call(&block)
    @actual_growth_kb > @max_growth_kb
  end

  failure_message do
    "expected memory growth to exceed #{format_mb(@max_growth_kb)}, " \
      "but grew by #{format_mb(@actual_growth_kb || 0)}"
  end

  failure_message_when_negated do
    "expected memory growth not to exceed #{format_mb(@max_growth_kb)}, " \
      "but grew by #{format_mb(@actual_growth_kb || 0)}"
  end

  def format_mb(kb)
    format("%.1f MB", kb / 1024.0)
  end

  supports_block_expectations
end
