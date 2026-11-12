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
