# frozen_string_literal: true

require "stringio"
require "tmpdir"
require "evilution/worker_database"
require "evilution/worker_database/copies"
require_relative "../support/fake_active_record"

RSpec.describe Evilution::WorkerDatabase do
  let(:stream) { StringIO.new }

  around do |example|
    saved = ENV.fetch("TEST_ENV_NUMBER", nil)
    ENV.delete("TEST_ENV_NUMBER")
    example.run
  ensure
    saved.nil? ? ENV.delete("TEST_ENV_NUMBER") : ENV["TEST_ENV_NUMBER"] = saved
  end

  def reconnect
    described_class.reconnect(stream: stream)
  end

  it "does nothing when ActiveRecord is not loaded" do
    FakeActiveRecord.install(self)
    hide_const("ActiveRecord")

    expect { reconnect }.not_to raise_error
    expect(stream.string).to eq("")
  end

  it "does nothing when ActiveRecord is loaded without a Rails application" do
    base = FakeActiveRecord.install(self)
    hide_const("Rails")
    ENV["TEST_ENV_NUMBER"] = "2"

    reconnect

    expect(base.establish_calls).to eq(0)
    expect(base.connection_db_config.configuration_hash[:database]).to eq("db/test.sqlite3")
    expect(stream.string).to eq("")
  end

  it "does nothing when Rails is loaded without an application" do
    base = FakeActiveRecord.install(self)
    stub_const("Rails", Module.new)
    ENV["TEST_ENV_NUMBER"] = "2"

    reconnect

    expect(base.establish_calls).to eq(0)
    expect(stream.string).to eq("")
  end

  it "does nothing when the Rails application is not defined yet" do
    base = FakeActiveRecord.install(self)
    rails = Module.new
    rails.define_singleton_method(:application) { nil }
    stub_const("Rails", rails)
    ENV["TEST_ENV_NUMBER"] = "2"

    reconnect

    expect(base.establish_calls).to eq(0)
    expect(stream.string).to eq("")
  end

  it "does nothing when ActiveRecord::Base has no connection to switch" do
    base = FakeActiveRecord.install(self)
    base.remove_connection
    ENV["TEST_ENV_NUMBER"] = "2"

    reconnect

    expect(base.establish_calls).to eq(0)
    expect(stream.string).to eq("")
  end

  it "does nothing on an ActiveRecord without per-connection db configs" do
    base = FakeActiveRecord.install(self)
    allow(base).to receive(:respond_to?).and_call_original
    allow(base).to receive(:respond_to?).with(:connection_db_config).and_return(false)
    ENV["TEST_ENV_NUMBER"] = "2"

    reconnect

    expect(base.establish_calls).to eq(0)
    expect(stream.string).to eq("")
  end

  it "reconnects to the database database.yml now resolves to" do
    base = FakeActiveRecord.install(self)
    ENV["TEST_ENV_NUMBER"] = "3"

    reconnect

    expect(base.establish_calls).to eq(1)
    expect(base.connection_db_config.configuration_hash[:database]).to eq("db/test3.sqlite3")
    expect(base.connection_db_config.env_name).to eq("test")
    expect(base.connection_db_config.name).to eq("primary")
    expect(stream.string).to eq("")
  end

  it "replaces the boot-time configurations with the re-rendered ones" do
    base = FakeActiveRecord.install(self)
    ENV["TEST_ENV_NUMBER"] = "2"

    reconnect

    expect(base.configurations.raw.dig("test", "database")).to eq("db/test2.sqlite3")
  end

  context "when the worker's database is not prepared" do
    let(:hint) do
      "Prepare it with `TEST_ENV_NUMBER=2 bin/rails db:test:prepare`."
    end

    def expect_preloaded_connection(base)
      expect(base.connection_db_config.configuration_hash[:database]).to eq("db/test.sqlite3")
      expect(base.configurations.raw.dig("test", "database")).to eq("db/test.sqlite3")
    end

    it "goes back to the preloaded database when the worker's database does not exist" do
      base = FakeActiveRecord.install(self)
      base.databases["db/test2.sqlite3"] = nil
      ENV["TEST_ENV_NUMBER"] = "2"

      reconnect

      expect_preloaded_connection(base)
      expect(base.establish_calls).to eq(2)
      expect(stream.string).to eq(
        "[evilution] worker database: db/test2.sqlite3 is not ready " \
        "(FakeActiveRecord::NoDatabaseError: database db/test2.sqlite3 does not exist); " \
        "this worker uses the preloaded db/test.sqlite3. #{hint}\n"
      )
    end

    it "goes back to the preloaded database when the worker's database has no schema" do
      base = FakeActiveRecord.install(self)
      base.databases["db/test2.sqlite3"] = { tables: [], versions: [] }
      ENV["TEST_ENV_NUMBER"] = "2"

      reconnect

      expect_preloaded_connection(base)
      expect(stream.string).to eq(
        "[evilution] worker database: db/test2.sqlite3 is not ready " \
        "(missing tables: schema_migrations, users); " \
        "this worker uses the preloaded db/test.sqlite3. #{hint}\n"
      )
    end

    it "goes back to the preloaded database when the worker's database lacks a migration" do
      base = FakeActiveRecord.install(self)
      base.databases["db/test.sqlite3"] = { tables: %w[schema_migrations users], versions: %w[1 2] }
      base.databases["db/test2.sqlite3"] = { tables: %w[schema_migrations users], versions: %w[1] }
      ENV["TEST_ENV_NUMBER"] = "2"

      reconnect

      expect_preloaded_connection(base)
      expect(stream.string).to include("(missing migrations: 2)")
    end

    it "accepts a worker database with extra tables and migrations" do
      base = FakeActiveRecord.install(self)
      base.databases["db/test.sqlite3"] = { tables: %w[schema_migrations users], versions: %w[1] }
      base.databases["db/test2.sqlite3"] = { tables: %w[schema_migrations users posts], versions: %w[1 2] }
      ENV["TEST_ENV_NUMBER"] = "2"

      reconnect

      expect(base.connection_db_config.configuration_hash[:database]).to eq("db/test2.sqlite3")
      expect(stream.string).to eq("")
    end

    it "compares migrations only when the preloaded database records them" do
      base = FakeActiveRecord.install(self)
      base.databases["db/test.sqlite3"] = { tables: %w[users], versions: nil }
      base.databases["db/test2.sqlite3"] = { tables: %w[users], versions: nil }
      ENV["TEST_ENV_NUMBER"] = "2"

      reconnect

      expect(base.connection_db_config.configuration_hash[:database]).to eq("db/test2.sqlite3")
      expect(stream.string).to eq("")
    end

    it "names an empty TEST_ENV_NUMBER in the hint when none is set" do
      rendered = FakeActiveRecord.sqlite_yml
      base = FakeActiveRecord.install(self) { rendered }
      rendered = { "test" => { "adapter" => "sqlite3", "database" => "db/other.sqlite3" } }
      base.databases["db/other.sqlite3"] = nil

      reconnect

      expect_preloaded_connection(base)
      expect(stream.string).to end_with("Prepare it with `TEST_ENV_NUMBER= bin/rails db:test:prepare`.\n")
    end

    it "lets an interrupt during the check through" do
      base = FakeActiveRecord.install(self)
      base.databases["db/test2.sqlite3"] = Interrupt
      ENV["TEST_ENV_NUMBER"] = "2"

      expect { reconnect }.to raise_error(Interrupt)
    end

    it "keeps the preloaded connection when the preloaded database cannot be read" do
      base = FakeActiveRecord.install(self)
      base.databases["db/test.sqlite3"] = nil
      ENV["TEST_ENV_NUMBER"] = "2"

      reconnect

      expect(base.establish_calls).to eq(0)
      expect(stream.string).to start_with("[evilution] worker database: kept the preloaded connection")
    end
  end

  context "when the app has connections besides ActiveRecord::Base's" do
    it "warns that they still use the preloaded databases" do
      base = FakeActiveRecord.install(self)
      base.add_pool("animals", "db/animals.sqlite3")
      base.add_pool("primary_replica", "db/test.sqlite3")
      ENV["TEST_ENV_NUMBER"] = "2"

      reconnect

      expect(base.connection_db_config.configuration_hash[:database]).to eq("db/test2.sqlite3")
      expect(stream.string).to eq(
        "[evilution] worker database: switched ActiveRecord::Base to db/test2.sqlite3, but other " \
        "connections still use the preloaded db/animals.sqlite3, db/test.sqlite3. See README.\n"
      )
    end

    it "lists the pools of other roles" do
      base = FakeActiveRecord.install(self)
      base.add_pool("primary_replica", "db/replica.sqlite3", role: :reading)
      ENV["TEST_ENV_NUMBER"] = "2"

      reconnect

      expect(stream.string).to include("the preloaded db/replica.sqlite3. See README.")
    end

    it "names each database once" do
      base = FakeActiveRecord.install(self)
      base.add_pool("animals", "db/animals.sqlite3")
      base.add_pool("animals_replica", "db/animals.sqlite3")
      ENV["TEST_ENV_NUMBER"] = "2"

      reconnect

      expect(stream.string).to include("the preloaded db/animals.sqlite3. See README.")
    end

    it "lists a separate pool built from ActiveRecord::Base's own config" do
      base = FakeActiveRecord.install(self)
      base.add_pool_sharing_config
      ENV["TEST_ENV_NUMBER"] = "2"

      reconnect

      expect(stream.string).to include("the preloaded db/test.sqlite3. See README.")
    end

    it "names a connection without a database path by its config name" do
      base = FakeActiveRecord.install(self)
      base.add_pool("animals", nil)
      ENV["TEST_ENV_NUMBER"] = "2"

      reconnect

      expect(stream.string).to include("the preloaded animals. See README.")
    end

    [NoMethodError, ArgumentError].each do |error|
      it "lists them on a Rails whose pool list rejects the :all role with #{error}" do
        base = FakeActiveRecord.install(self)
        base.legacy_pool_list = error
        base.add_pool("animals", "db/animals.sqlite3")
        ENV["TEST_ENV_NUMBER"] = "2"

        reconnect

        expect(base.connection_db_config.configuration_hash[:database]).to eq("db/test2.sqlite3")
        expect(stream.string).to eq(
          "[evilution] worker database: switched ActiveRecord::Base to db/test2.sqlite3, but other " \
          "connections still use the preloaded db/animals.sqlite3. See README.\n"
        )
      end
    end

    it "says nothing about them when the worker kept the preloaded database" do
      base = FakeActiveRecord.install(self)
      base.add_pool("animals", "db/animals.sqlite3")
      base.databases["db/test2.sqlite3"] = nil
      ENV["TEST_ENV_NUMBER"] = "2"

      reconnect

      expect(stream.string).not_to include("animals")
      expect(stream.string).not_to include("switched")
    end
  end

  it "keeps the connection when database.yml resolves to the same database" do
    base = FakeActiveRecord.install(self)
    ENV["TEST_ENV_NUMBER"] = ""

    reconnect

    expect(base.establish_calls).to eq(0)
    expect(base.configurations.raw.dig("test", "database")).to eq("db/test.sqlite3")
    expect(stream.string).to eq("")
  end

  it "keeps a connection the app established outside database.yml" do
    base = FakeActiveRecord.install(self)
    base.use_custom_connection({ adapter: "sqlite3", database: ":memory:" })
    ENV["TEST_ENV_NUMBER"] = "2"

    reconnect

    expect(base.establish_calls).to eq(0)
    expect(base.connection_db_config.configuration_hash[:database]).to eq(":memory:")
    expect(stream.string).to eq("")
  end

  it "keeps a connection whose environment database.yml does not define" do
    base = FakeActiveRecord.install(self)
    base.use_custom_connection({ adapter: "sqlite3", database: "db/ci.sqlite3" }, env_name: "ci")
    ENV["TEST_ENV_NUMBER"] = "2"

    reconnect

    expect(base.establish_calls).to eq(0)
    expect(stream.string).to eq("")
  end

  it "keeps the connection when the re-rendered database.yml lacks its environment" do
    rendered = FakeActiveRecord.sqlite_yml
    base = FakeActiveRecord.install(self) { rendered }
    rendered = { "development" => { "adapter" => "sqlite3" } }

    reconnect

    expect(base.establish_calls).to eq(0)
    expect(base.connection_db_config.configuration_hash[:database]).to eq("db/test.sqlite3")
    expect(stream.string).to eq("")
  end

  it "warns and keeps going when re-rendering database.yml fails" do
    raise_now = false
    base = FakeActiveRecord.install(self) do
      raise ArgumentError, "bad ERB" if raise_now

      FakeActiveRecord.sqlite_yml
    end
    raise_now = true

    expect { reconnect }.not_to raise_error
    expect(stream.string).to eq("[evilution] worker database: kept the preloaded connection (ArgumentError: bad ERB)\n")
    expect(base.establish_calls).to eq(0)
  end

  it "lets an interrupt through" do
    FakeActiveRecord.install(self)
    allow(Rails).to receive(:application).and_raise(Interrupt)

    expect { reconnect }.to raise_error(Interrupt)
  end

  it "writes its warning to $stderr by default" do
    FakeActiveRecord.install(self)
    allow(Rails).to receive(:application).and_raise(ArgumentError, "boom")

    expect { described_class.reconnect }.to output(/ArgumentError: boom/).to_stderr
  end

  describe ".app_booted?" do
    it "is true when a Rails application's ActiveRecord is loaded" do
      FakeActiveRecord.install(self)

      expect(described_class.app_booted?).to be(true)
    end

    it "is false when ActiveRecord is not loaded" do
      FakeActiveRecord.install(self)
      hide_const("ActiveRecord")

      expect(described_class.app_booted?).to be(false)
    end

    it "is false when Rails has no application" do
      FakeActiveRecord.install(self)
      stub_const("Rails", Module.new)

      expect(described_class.app_booted?).to be(false)
    end
  end

  describe ".copies_cover?" do
    def install_with(database)
      FakeActiveRecord.install(self) { { "test" => { "adapter" => "sqlite3", "database" => database } } }
    end

    it "is true when the preloaded connection is the SQLite file database.yml names" do
      install_with("db/test.sqlite3")

      expect(described_class.copies_cover?).to be(true)
    end

    it "is false when no Rails application is booted" do
      FakeActiveRecord.install(self)
      hide_const("ActiveRecord")

      expect(described_class.copies_cover?).to be(false)
    end

    it "is false when ActiveRecord::Base has no connection" do
      FakeActiveRecord.install(self).remove_connection

      expect(described_class.copies_cover?).to be(false)
    end

    it "is false for a file: URI, which a copy could not keep" do
      install_with("file:db/test.sqlite3")

      expect(described_class.copies_cover?).to be(false)
    end

    it "is false for a database other than SQLite" do
      FakeActiveRecord.install(self) { { "test" => { "adapter" => "postgresql", "database" => "app_test" } } }

      expect(described_class.copies_cover?).to be(false)
    end

    it "is false when the connection no longer matches database.yml" do
      base = install_with("db/test.sqlite3")
      base.use_custom_connection({ adapter: "sqlite3", database: "db/other.sqlite3" })

      expect(described_class.copies_cover?).to be(false)
    end

    it "is false when database.yml cannot be read" do
      base = install_with("db/test.sqlite3")
      allow(base).to receive(:configurations).and_raise(ArgumentError, "boom")

      expect(described_class.copies_cover?).to be(false)
    end

    it "lets an interrupt through" do
      base = install_with("db/test.sqlite3")
      allow(base).to receive(:configurations).and_raise(Interrupt)

      expect { described_class.copies_cover? }.to raise_error(Interrupt)
    end
  end

  context "with per-worker copies of a shared SQLite database" do
    around do |example|
      Dir.mktmpdir("evilution-worker-db") do |dir|
        @dir = dir
        example.run
      end
    end

    let(:copies) { Evilution::WorkerDatabase::Copies.new(root: File.join(@dir, "copies")) }
    let(:copy_path) { File.join(@dir, "copies", "worker-#{Process.pid}", "test.sqlite3") }
    let(:app_root) { File.join(@dir, "app") }
    let(:shared_yml) { { "test" => { "adapter" => "sqlite3", "database" => "db/test.sqlite3", "pool" => 5 } } }
    let(:copied) { [] }

    before do
      calls = copied
      allow(Evilution::WorkerDatabase::SqliteCopy).to receive(:call) { |source, destination| calls << [source, destination] }
    end

    def reconnect
      described_class.reconnect(stream: stream, copies: copies)
    end

    def install_shared
      yml = shared_yml
      FakeActiveRecord.install(self, root: app_root) { yml }
    end

    def primary(base)
      base.configurations.configs_for(env_name: "test", name: "primary")
    end

    it "connects the worker to its own copy when database.yml names one database for every worker" do
      base = install_shared
      ENV["TEST_ENV_NUMBER"] = "2"

      reconnect

      expect(copied).to eq([[File.join(app_root, "db/test.sqlite3"), copy_path]])
      expect(base.establish_calls).to eq(1)
      expect(base.connection_db_config.configuration_hash).to eq({ adapter: "sqlite3", database: copy_path, pool: 5 })
      expect(base.connection_db_config.env_name).to eq("test")
      expect(base.connection_db_config.name).to eq("primary")
      expect(stream.string).to eq("")
    end

    it "leaves the preloaded db config as it was" do
      base = install_shared
      preloaded = base.connection_db_config

      reconnect

      expect(preloaded.configuration_hash[:database]).to eq("db/test.sqlite3")
    end

    it "replaces only the copied database's entry in the configurations" do
      base = install_shared
      config = lambda do |env, name, db|
        hash = { adapter: "sqlite3", database: db, pool: 5 }
        FakeActiveRecord::DbConfig.new(env_name: +env, name: +name, configuration_hash: hash)
      end
      entries = [config.call("test", "primary", "db/test.sqlite3"), config.call("test", "animals", "db/animals.sqlite3"),
                 config.call("development", "primary", "db/development.sqlite3")]
      base.configurations = FakeActiveRecord::Configurations.new(entries.dup)
      previous = base.configurations

      reconnect

      databases = base.configurations.configurations.map { |c| [c.env_name, c.name, c.configuration_hash[:database]] }
      expect(databases).to eq([%w[test primary] + [copy_path], %w[test animals db/animals.sqlite3],
                               %w[development primary db/development.sqlite3]])
      expect(previous.configurations).to eq(entries)
    end

    it "points the configurations at the copy, so reconnecting by environment name keeps it" do
      base = install_shared

      reconnect

      expect(primary(base).configuration_hash[:database]).to eq(copy_path)
    end

    it "keeps the configurations of other environments" do
      yml = shared_yml.merge("development" => { "adapter" => "sqlite3", "database" => "db/development.sqlite3" })
      base = FakeActiveRecord.install(self, root: app_root) { yml }

      reconnect

      development = base.configurations.configs_for(env_name: "development", name: "primary")
      expect(development.configuration_hash[:database]).to eq("db/development.sqlite3")
    end

    it "copies an absolute database path as it is" do
      absolute = File.join(@dir, "shared", "test.sqlite3")
      yml = { "test" => { "adapter" => "sqlite3", "database" => absolute } }
      FakeActiveRecord.install(self, root: app_root) { yml }

      reconnect

      expect(copied).to eq([[absolute, copy_path]])
    end

    it "resolves a relative path against the working directory when Rails has no root" do
      yml = shared_yml
      FakeActiveRecord.install(self) { yml }

      reconnect

      expect(copied).to eq([[File.expand_path("db/test.sqlite3"), copy_path]])
    end

    it "copies for the first worker too, whose database.yml database is the preloaded one" do
      base = FakeActiveRecord.install(self, root: app_root)
      ENV["TEST_ENV_NUMBER"] = ""

      reconnect

      expect(copied.length).to eq(1)
      expect(base.connection_db_config.configuration_hash[:database]).to eq(copy_path)
    end

    it "uses the worker's own prepared database from database.yml instead of a copy" do
      base = FakeActiveRecord.install(self, root: app_root)
      ENV["TEST_ENV_NUMBER"] = "2"

      reconnect

      expect(copied).to eq([])
      expect(base.connection_db_config.configuration_hash[:database]).to eq("db/test2.sqlite3")
    end

    it "copies the preloaded database when the worker's own database is not prepared" do
      base = FakeActiveRecord.install(self, root: app_root)
      base.databases["db/test2.sqlite3"] = nil
      ENV["TEST_ENV_NUMBER"] = "2"

      reconnect

      expect(base.connection_db_config.configuration_hash[:database]).to eq(copy_path)
      expect(stream.string).to eq(
        "[evilution] worker database: db/test2.sqlite3 is not ready " \
        "(FakeActiveRecord::NoDatabaseError: database db/test2.sqlite3 does not exist); " \
        "this worker uses a copy of the preloaded db/test.sqlite3. " \
        "Prepare it with `TEST_ENV_NUMBER=2 bin/rails db:test:prepare`.\n"
      )
    end

    it "copies nothing when copies are off" do
      base = install_shared

      described_class.reconnect(stream: stream)
      described_class.new(stream: stream, copies: Evilution::WorkerDatabase::Copies::NONE).reconnect

      expect(copied).to eq([])
      expect(base.establish_calls).to eq(0)
    end

    it "copies nothing for a database other than SQLite" do
      yml = { "test" => { "adapter" => "postgresql", "database" => "app_test" } }
      base = FakeActiveRecord.install(self, root: app_root) { yml }

      reconnect

      expect(copied).to eq([])
      expect(base.establish_calls).to eq(0)
      expect(stream.string).to eq("")
    end

    it "copies nothing for an in-memory database" do
      yml = { "test" => { "adapter" => "sqlite3", "database" => ":memory:" } }
      base = FakeActiveRecord.install(self, root: app_root) { yml }

      reconnect

      expect(copied).to eq([])
      expect(base.establish_calls).to eq(0)
    end

    it "keeps a connection the app established outside database.yml" do
      base = install_shared
      base.use_custom_connection({ adapter: "sqlite3", database: "db/elsewhere.sqlite3" })

      reconnect

      expect(copied).to eq([])
      expect(base.establish_calls).to eq(0)
    end

    it "warns that other connections still share the preloaded databases" do
      base = install_shared
      base.add_pool("animals", "db/animals.sqlite3")

      reconnect

      expect(stream.string).to eq(
        "[evilution] worker database: switched ActiveRecord::Base to #{copy_path}, but other " \
        "connections still use the preloaded db/animals.sqlite3. See README.\n"
      )
    end

    context "when the copy fails" do
      before do
        allow(Evilution::WorkerDatabase::SqliteCopy).to receive(:call).and_raise(IOError, "disk full")
      end

      it "keeps the shared database and says so" do
        base = install_shared

        reconnect

        expect(base.establish_calls).to eq(0)
        expect(base.connection_db_config.configuration_hash[:database]).to eq("db/test.sqlite3")
        expect(primary(base).configuration_hash[:database]).to eq("db/test.sqlite3")
        expect(stream.string).to eq(
          "[evilution] worker database: could not copy db/test.sqlite3 (IOError: disk full); " \
          "this worker shares it with the other workers.\n"
        )
      end

      it "reports both the unprepared database and the failed copy" do
        base = FakeActiveRecord.install(self, root: app_root)
        base.databases["db/test2.sqlite3"] = nil
        ENV["TEST_ENV_NUMBER"] = "2"

        reconnect

        expect(base.connection_db_config.configuration_hash[:database]).to eq("db/test.sqlite3")
        expect(stream.string.lines.length).to eq(2)
        expect(stream.string.lines.last).to start_with("[evilution] worker database: could not copy db/test.sqlite3")
      end
    end

    it "lets an interrupt during the copy through" do
      allow(Evilution::WorkerDatabase::SqliteCopy).to receive(:call).and_raise(Interrupt)
      install_shared

      expect { reconnect }.to raise_error(Interrupt)
    end
  end
end
