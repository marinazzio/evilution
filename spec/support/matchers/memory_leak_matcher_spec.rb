# frozen_string_literal: true

require_relative "memory_leak_matcher"

RSpec.describe "leak_memory matcher" do
  # Mapped buffers, written to, take fresh pages of the process whatever the
  # allocator had free, as a native extension that leaks would.
  it "catches a block that keeps memory outside the GC heap" do
    leaked = []

    expect { leaked << IO::Buffer.new(300_000).tap { |buffer| buffer.clear(1) } }
      .to leak_memory.over(5).by_more_than(1_024)
    expect(leaked).to all(be_mapped)
  end

  it "catches a block that keeps many small objects, which live in the GC heap" do
    leaked = []

    expect { 10_000.times { leaked << Object.new } }.to leak_memory.over(5).by_more_than(1_024)
    expect(leaked).not_to be_empty
  end
end
