# frozen_string_literal: true

require "evilution/integration/loading/test_class_cache"

RSpec.describe Evilution::Integration::Loading::TestClassCache do
  let(:registry) { [] }

  subject(:cache) { described_class.new { registry.dup } }

  it "returns the classes that registered while each file loaded" do
    classes = cache.fetch(%w[a_test.rb b_test.rb]) { |file| registry << file.to_sym }

    expect(classes).to eq(%i[a_test.rb b_test.rb])
  end

  it "leaves out classes that were registered before the load" do
    registry << :earlier

    expect(cache.fetch(["a_test.rb"]) { registry << :a }).to eq([:a])
  end

  it "loads a file once and returns the same classes afterwards" do
    loads = []
    load = lambda do |file|
      loads << file
      registry << :a
    end

    first = cache.fetch(["a_test.rb"], &load)
    second = cache.fetch(["a_test.rb"], &load)

    expect(loads).to eq(["a_test.rb"])
    expect(second).to eq(first)
  end

  it "returns only the classes of the files asked for" do
    cache.fetch(["a_test.rb"]) { registry << :a }

    expect(cache.fetch(["b_test.rb"]) { registry << :b }).to eq([:b])
  end

  it "lists a class two files registered once" do
    shared = %i[shared]
    cache.fetch(["a_test.rb"]) { registry.concat(shared) }
    registry.clear
    cache.fetch(["b_test.rb"]) { registry.concat(shared) }

    expect(cache.fetch(%w[a_test.rb b_test.rb]) { raise "loaded again" }).to eq(shared)
  end

  it "remembers a file that registered nothing" do
    loads = 0
    2.times { cache.fetch(["empty_test.rb"]) { loads += 1 } }

    expect(loads).to eq(1)
  end

  context "when a load raises" do
    it "lets the error through and loads the file again next time" do
      expect { cache.fetch(["a_test.rb"]) { raise ArgumentError, "boom" } }.to raise_error(ArgumentError, "boom")

      expect(cache.fetch(["a_test.rb"]) { registry << :a }).to eq([:a])
    end

    # The class is defined by then, so the next load reopens it and registers
    # nothing.
    it "keeps the classes that had registered before the error" do
      failing = lambda do |_file|
        registry << :a
        raise ArgumentError, "boom"
      end
      expect { cache.fetch(["a_test.rb"], &failing) }.to raise_error(ArgumentError)

      expect(cache.fetch(["a_test.rb"]) { registry << :b }).to eq(%i[a b])
    end
  end

  describe "#clear" do
    it "forgets every file" do
      loads = 0
      cache.fetch(["a_test.rb"]) { loads += 1 }
      cache.clear
      cache.fetch(["a_test.rb"]) { loads += 1 }

      expect(loads).to eq(2)
    end
  end
end
