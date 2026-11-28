# frozen_string_literal: true

require_relative "memory_leak_matcher"

RSpec.describe "leak_memory matcher" do
  # Mapped buffers, written to, take fresh pages of the process whatever the
  # allocator had free, as a native extension that leaks would.
  context "with a block that keeps memory outside the GC heap" do
    # IO::Buffer warns on first use that it is experimental.
    around do |example|
      experimental = Warning[:experimental]
      Warning[:experimental] = false
      example.run
    ensure
      Warning[:experimental] = experimental
    end

    it "catches the leak" do
      leaked = []

      expect { leaked << IO::Buffer.new(300_000).tap { |buffer| buffer.clear(1) } }
        .to leak_memory.over(5).by_more_than(1_024)
      expect(leaked).to all(be_mapped)
    end

    # Each pass frees as much room in the GC heap as it leaks outside it, room
    # the process keeps or hands back to the system.
    it "catches the leak while objects the process held before are freed" do
      held = Array.new(60) { Array.new(10_000) { Object.new } }
      leaked = []

      expect do
        held.pop
        leaked << IO::Buffer.new(400_000).tap { |buffer| buffer.clear(1) }
      end.to leak_memory.over(5).by_more_than(1_024)
      expect(leaked).to all(be_mapped)
    end
  end

  it "catches a block that keeps many small objects, which live in the GC heap" do
    leaked = []

    expect { 10_000.times { leaked << Object.new } }.to leak_memory.over(5).by_more_than(1_024)
    expect(leaked).not_to be_empty
  end
end
