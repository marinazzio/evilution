# frozen_string_literal: true

require "stringio"
require "evilution/worker_database"
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
end
