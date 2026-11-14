# frozen_string_literal: true

require "tmpdir"
require "fileutils"
require "evilution/worker_database/copies"

RSpec.describe Evilution::WorkerDatabase::Copies do
  around do |example|
    Dir.mktmpdir("evilution-copies") do |dir|
      @dir = dir
      example.run
    end
  end

  let(:root) { File.join(@dir, "root") }
  let(:copies) { described_class.new(root: root) }

  it "is enabled" do
    expect(copies.enabled?).to be(true)
  end

  describe "default root" do
    it "is a directory of its own under the system temp dir, named after this process" do
      first = described_class.new.root
      second = described_class.new.root

      expect(File.dirname(first)).to eq(Dir.tmpdir)
      expect(File.basename(first)).to start_with("evilution-worker-db-#{Process.pid}-")
      expect(first).not_to eq(second)
    end

    it "is not created until a worker copies into it" do
      expect(File.exist?(described_class.new.root)).to be(false)
    end
  end

  describe "#provision" do
    it "copies the database into a directory of the calling process and returns the copy's path" do
      allow(Evilution::WorkerDatabase::SqliteCopy).to receive(:call)
      source = "/srv/app/db/test.sqlite3"

      path = copies.provision(source)

      expect(path).to eq(File.join(root, "worker-#{Process.pid}", "test.sqlite3"))
      expect(Evilution::WorkerDatabase::SqliteCopy).to have_received(:call).with(source, path)
    end

    it "lets a failed copy through" do
      allow(Evilution::WorkerDatabase::SqliteCopy).to receive(:call).and_raise(IOError, "disk full")

      expect { copies.provision("/srv/app/db/test.sqlite3") }.to raise_error(IOError, "disk full")
    end
  end

  describe "#remove" do
    it "deletes every worker's copies" do
      FileUtils.mkdir_p(File.join(root, "worker-1"))
      File.write(File.join(root, "worker-1", "test.sqlite3"), "db")

      copies.remove

      expect(File.exist?(root)).to be(false)
    end

    it "does nothing when no worker made a copy" do
      expect { copies.remove }.not_to raise_error
      expect(File.exist?(root)).to be(false)
    end
  end

  describe "NONE" do
    it "is disabled and has nothing to remove" do
      expect(described_class::NONE.enabled?).to be(false)
      expect { described_class::NONE.remove }.not_to raise_error
    end
  end
end
