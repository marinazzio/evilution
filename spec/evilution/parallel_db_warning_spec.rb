# frozen_string_literal: true

require "spec_helper"
require "fileutils"
require "tmpdir"
require "stringio"
require "evilution/parallel_db_warning"

RSpec.describe Evilution::ParallelDbWarning do
  around do |example|
    Dir.mktmpdir("evilution-parallel-db-warning") do |tmp|
      @tmp = tmp
      example.run
    end
  end

  def write_database_yml(content)
    FileUtils.mkdir_p(File.join(@tmp, "config"))
    File.write(File.join(@tmp, "config", "database.yml"), content)
  end

  def sqlite_yml
    <<~YAML
      default: &default
        adapter: sqlite3
        pool: 5
      test:
        <<: *default
        database: db/test.sqlite3
    YAML
  end

  def postgres_yml
    <<~YAML
      default: &default
        adapter: postgresql
        host: localhost
      test:
        <<: *default
        database: app_test
    YAML
  end

  def mixed_yml_test_postgres
    <<~YAML
      development:
        adapter: sqlite3
        database: db/development.sqlite3
      test:
        adapter: postgresql
        host: localhost
        database: app_test
    YAML
  end

  def erb_yml
    <<~YAML
      test:
        adapter: sqlite3
        database: db/test<%= ENV['TEST_ENV_NUMBER'] %>.sqlite3
    YAML
  end

  def unparseable_yml
    "test:\n  adapter: sqlite3\n  database: db/test<%= undefined_erb_helper_xyz %>.sqlite3\n"
  end

  def call_warn(jobs:, root: @tmp)
    io = StringIO.new
    config = instance_double(Evilution::Config, jobs: jobs)
    described_class.warn_if_sqlite_parallel(config, output: io, root: root)
    io.string
  end

  describe ".warn_if_sqlite_parallel" do
    it "warns when jobs > 1 and database.yml uses sqlite3" do
      write_database_yml(sqlite_yml)
      expect(call_warn(jobs: 2)).to include("SQLite").and(include("TEST_ENV_NUMBER"))
    end

    it "does not warn when jobs == 1" do
      write_database_yml(sqlite_yml)
      expect(call_warn(jobs: 1)).to eq("")
    end

    it "does not warn when database.yml uses a non-sqlite adapter" do
      write_database_yml(postgres_yml)
      expect(call_warn(jobs: 4)).to eq("")
    end

    it "does not warn when database.yml is absent" do
      expect(call_warn(jobs: 4)).to eq("")
    end

    # Regression for Copilot review on PR #819: earlier implementation
    # pattern-matched "sqlite3" anywhere in the file, so dev/prod using SQLite
    # with test on Postgres/MySQL still fired the warning.
    it "does not warn when only non-test environments use sqlite3" do
      write_database_yml(mixed_yml_test_postgres)
      described_class.reset!
      expect(call_warn(jobs: 2)).to eq("")
    end

    it "warns when test: uses sqlite3 via ERB-interpolated database path" do
      write_database_yml(erb_yml)
      described_class.reset!
      expect(call_warn(jobs: 2)).to include("SQLite")
    end

    it "does not warn when database.yml cannot be parsed safely" do
      write_database_yml(unparseable_yml)
      described_class.reset!
      expect(call_warn(jobs: 2)).to eq("")
    end

    it "does not warn twice for the same root" do
      write_database_yml(sqlite_yml)
      described_class.reset!
      first = call_warn(jobs: 2)
      second = call_warn(jobs: 2)
      expect(first).not_to eq("")
      expect(second).to eq("")
    end

    it "warns again after reset!" do
      write_database_yml(sqlite_yml)
      described_class.reset!
      call_warn(jobs: 2)
      described_class.reset!
      expect(call_warn(jobs: 2)).not_to eq("")
    end
  end
end
