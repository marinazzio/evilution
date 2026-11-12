# frozen_string_literal: true

require "evilution/worker_database"
require_relative "../../support/fake_active_record"

RSpec.describe Evilution::WorkerDatabase::Schema do
  def schema(tables:, versions: [])
    described_class.new(tables: tables, versions: versions)
  end

  describe ".of" do
    it "reads the tables and applied migrations of the connection's database" do
      base = FakeActiveRecord.install(self)
      base.databases["db/test.sqlite3"] = { tables: %w[users schema_migrations], versions: [2, 1] }

      read = described_class.of(base)

      expect(read.tables).to eq(%w[schema_migrations users])
      expect(read.versions).to eq(%w[1 2])
    end

    it "reads no migrations from a database without a migrations table" do
      base = FakeActiveRecord.install(self)
      base.databases["db/test.sqlite3"] = { tables: %w[users], versions: nil }

      expect(described_class.of(base).versions).to eq([])
    end
  end

  describe "#missing_from" do
    let(:reference) { schema(tables: %w[schema_migrations users posts], versions: %w[1 2]) }

    it "is nil when the database has every table and migration" do
      expect(schema(tables: %w[posts schema_migrations users], versions: %w[2 1]).missing_from(reference)).to be_nil
    end

    it "is nil when the database has more than the reference" do
      worker = schema(tables: %w[comments posts schema_migrations users], versions: %w[1 2 3])

      expect(worker.missing_from(reference)).to be_nil
    end

    it "names the missing tables in order" do
      expect(schema(tables: %w[users], versions: %w[1 2]).missing_from(reference))
        .to eq("missing tables: posts, schema_migrations")
    end

    it "reports missing tables before missing migrations" do
      expect(schema(tables: [], versions: []).missing_from(reference)).to start_with("missing tables:")
    end

    it "names the missing migrations in order" do
      reference = schema(tables: %w[users], versions: %w[3 1 2])

      expect(schema(tables: %w[users], versions: %w[1]).missing_from(reference))
        .to eq("missing migrations: 2, 3")
    end
  end
end
