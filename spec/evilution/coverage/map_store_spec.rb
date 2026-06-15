# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "evilution/coverage/map"
require "evilution/coverage/map_store"

RSpec.describe Evilution::Coverage::MapStore do
  around do |example|
    Dir.mktmpdir do |dir|
      @dir = dir
      example.run
    end
  end

  attr_reader :dir

  # Two real source files so per-file digests can be exercised independently.
  def write_source(name, content)
    path = File.join(dir, name)
    File.write(path, content)
    path
  end

  let(:calc) { write_source("calc.rb", "def add(a, b) = a + b\n") }
  let(:util) { write_source("util.rb", "def noop = nil\n") }

  let(:map) do
    Evilution::Coverage::Map.new(
      index: {
        calc => { 1 => ["spec/calc_spec.rb:5"] },
        util => { 1 => ["spec/util_spec.rb:3"] }
      },
      built_files: [calc, util]
    )
  end

  subject(:store) { described_class.new(root: File.join(dir, ".evilution/coverage")) }

  describe "#save / #load roundtrip" do
    it "returns a map equivalent to the saved one when every file is unchanged" do
      store.save(map, [calc, util])
      loaded = store.load([calc, util])

      expect(loaded.examples_for(calc, 1)).to eq(["spec/calc_spec.rb:5"])
      expect(loaded.examples_for(util, 1)).to eq(["spec/util_spec.rb:3"])
      expect(loaded.built?(calc)).to be(true)
      expect(loaded.built?(util)).to be(true)
    end
  end

  describe "partial invalidation" do
    it "drops a changed file's entries while keeping the unchanged file" do
      store.save(map, [calc, util])
      File.write(calc, "def add(a, b) = a + b + 1\n") # calc now stale

      loaded = store.load([calc, util])

      # Stale file: pruned -> not built -> caller falls back.
      expect(loaded.examples_for(calc, 1)).to eq([])
      expect(loaded.built?(calc)).to be(false)
      # Fresh file: still served.
      expect(loaded.examples_for(util, 1)).to eq(["spec/util_spec.rb:3"])
      expect(loaded.built?(util)).to be(true)
    end

    it "drops a file that has since been deleted" do
      store.save(map, [calc, util])
      File.delete(util)

      loaded = store.load([calc, util])
      expect(loaded.built?(util)).to be(false)
      expect(loaded.built?(calc)).to be(true)
    end
  end

  describe "#stale_files" do
    it "is empty when all files are unchanged" do
      store.save(map, [calc, util])
      expect(store.stale_files([calc, util])).to eq([])
    end

    it "lists files whose content changed" do
      store.save(map, [calc, util])
      File.write(calc, "def add(a, b) = 0\n")
      expect(store.stale_files([calc, util])).to eq([calc])
    end

    it "treats every file as stale when there is no cache" do
      expect(store.stale_files([calc, util])).to contain_exactly(calc, util)
    end
  end

  describe "missing / corrupt cache" do
    it "returns nil when no cache file exists (caller rebuilds)" do
      expect(store.load([calc, util])).to be_nil
    end

    it "returns nil when the cache file is corrupt (caller rebuilds)" do
      store.save(map, [calc, util])
      File.write(File.join(dir, ".evilution/coverage/map.json"), "{ not valid json")
      expect(store.load([calc, util])).to be_nil
    end
  end
end
