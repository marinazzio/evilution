# frozen_string_literal: true

require "tmpdir"
require "fileutils"
require "evilution/worker_database/sqlite_copy"

RSpec.describe Evilution::WorkerDatabase::SqliteCopy do
  describe ".copyable?" do
    def copyable?(hash)
      described_class.copyable?(hash)
    end

    it "accepts a SQLite database file" do
      expect(copyable?({ adapter: "sqlite3", database: "db/test.sqlite3" })).to be(true)
    end

    it "accepts an absolute SQLite database path" do
      expect(copyable?({ adapter: "sqlite3", database: "/srv/app/db/test.sqlite3" })).to be(true)
    end

    it "accepts an adapter given as a symbol" do
      expect(copyable?({ adapter: :sqlite3, database: "db/test.sqlite3" })).to be(true)
    end

    it "rejects an in-memory database, which no two processes share" do
      expect(copyable?({ adapter: "sqlite3", database: String.new(":memory:") })).to be(false)
    end

    it "rejects a file: URI, whose parameters a copy could not keep" do
      expect(copyable?({ adapter: "sqlite3", database: "file:db/test.sqlite3?mode=ro" })).to be(false)
    end

    it "rejects another adapter" do
      expect(copyable?({ adapter: "postgresql", database: "app_test" })).to be(false)
    end

    it "rejects a config without an adapter" do
      expect(copyable?({ database: "db/test.sqlite3" })).to be(false)
    end

    it "rejects a config without a database" do
      expect(copyable?({ adapter: "sqlite3" })).to be(false)
    end

    it "rejects an empty database name" do
      expect(copyable?({ adapter: "sqlite3", database: "" })).to be(false)
    end
  end

  describe ".call" do
    # Stands in for the sqlite3 gem: records what is opened, backed up and
    # closed, and writes the destination file the way SQLite would.
    let(:log) { [] }
    let(:status) { 101 }

    around do |example|
      Dir.mktmpdir("evilution-sqlite-copy") do |dir|
        @dir = dir
        example.run
      end
    end

    before { install_sqlite3 }

    def install_sqlite3
      stub_const("SQLite3::Database", fake_database(log))
      stub_const("SQLite3::Backup", fake_backup(log, -> { status }))
      stub_const("SQLite3::Constants::ErrorCode::DONE", 101)
    end

    def fake_database(calls)
      Class.new do
        attr_reader :path

        define_method(:initialize) do |path, **options|
          @path = path
          calls << [:existed, path] if !options[:readonly] && File.exist?(path)
          calls << [:open, path, options]
          File.write(path, "copied") unless options[:readonly]
        end

        define_method(:close) { calls << [:close, @path] }
      end
    end

    def fake_backup(calls, step_status)
      Class.new do
        define_method(:initialize) do |to, to_name, from, from_name|
          calls << [:backup, to.path, to_name, from.path, from_name]
        end

        define_method(:step) do |pages|
          calls << [:step, pages]
          step_status.call
        end

        define_method(:finish) { calls << [:finish] }
      end
    end

    let(:source) { File.join(@dir, "test.sqlite3") }
    let(:destination) { File.join(@dir, "copies", "worker-1", "test.sqlite3") }

    def write_source
      File.write(source, "original")
    end

    it "copies the whole database in one backup step from a read-only source" do
      write_source

      described_class.call(source, destination)

      expect(log).to eq(
        [
          [:open, source, { readonly: true }],
          [:open, destination, {}],
          [:backup, destination, "main", source, "main"],
          [:step, -1],
          [:finish],
          [:close, destination],
          [:close, source]
        ]
      )
      expect(File.read(destination)).to eq("copied")
    end

    it "removes what an earlier copy at the destination left behind" do
      write_source
      FileUtils.mkdir_p(File.dirname(destination))
      ["", "-wal", "-shm", "-journal"].each { |suffix| File.write("#{destination}#{suffix}", "stale") }

      described_class.call(source, destination)

      expect(log).not_to include([:existed, destination])
      %w[-wal -shm -journal].each { |suffix| expect(File.exist?("#{destination}#{suffix}")).to be(false) }
    end

    it "loads the sqlite3 gem when the app has not loaded it yet" do
      write_source
      hide_const("SQLite3")
      allow(described_class).to receive(:require).with("sqlite3") do
        install_sqlite3
        true
      end

      described_class.call(source, destination)

      expect(described_class).to have_received(:require).with("sqlite3")
      expect(File.read(destination)).to eq("copied")
    end

    it "does not load the sqlite3 gem again when it is loaded" do
      write_source
      allow(described_class).to receive(:require)

      described_class.call(source, destination)

      expect(described_class).not_to have_received(:require)
    end

    it "does not touch the source's own companion files" do
      write_source
      File.write("#{source}-wal", "log")

      described_class.call(source, destination)

      expect(File.read("#{source}-wal")).to eq("log")
    end

    context "when the backup does not complete" do
      let(:status) { 5 }

      it "raises and still closes both databases" do
        write_source

        expect { described_class.call(source, destination) }
          .to raise_error(described_class::Incomplete, "copying #{source} stopped with SQLite status 5")
        expect(log.last(3)).to eq([[:finish], [:close, destination], [:close, source]])
      end
    end

    it "raises without opening anything when the source does not exist" do
      expect { described_class.call(source, destination) }.to raise_error(Errno::ENOENT, /#{Regexp.escape(source)}/)
      expect(log).to eq([])
    end

    it "closes the source when the destination cannot be opened" do
      write_source
      allow(SQLite3::Database).to receive(:new).and_call_original
      allow(SQLite3::Database).to receive(:new).with(destination).and_raise(IOError, "disk full")

      expect { described_class.call(source, destination) }.to raise_error(IOError, "disk full")
      expect(log).to eq([[:open, source, { readonly: true }], [:close, source]])
    end
  end
end
