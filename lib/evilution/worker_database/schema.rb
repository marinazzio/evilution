# frozen_string_literal: true

require_relative "../worker_database"

# The part of a database's schema that tells whether a worker can use it in
# place of the preloaded one: its tables and, when it records them, its applied
# migrations. Read through the connection API common to ActiveRecord 6.1-8.x,
# so it works without migration files and with schema.rb or structure.sql.
class Evilution::WorkerDatabase::Schema
  attr_reader :tables, :versions

  def self.of(base)
    base.connection_pool.with_connection do |conn|
      new(tables: conn.tables, versions: versions(conn, base.schema_migrations_table_name))
    end
  end

  def self.versions(conn, table)
    return [] unless conn.table_exists?(table)

    conn.select_values("SELECT version FROM #{conn.quote_table_name(table)}")
  end
  private_class_method :versions

  def initialize(tables:, versions:)
    @tables = tables.sort
    @versions = versions.map(&:to_s).sort
  end

  # What this database lacks compared to the reference, or nil when it has
  # everything. Extra tables and migrations are fine.
  def missing_from(reference)
    tables = reference.tables - self.tables
    return "missing tables: #{tables.join(", ")}" unless tables.empty?

    versions = reference.versions - self.versions
    "missing migrations: #{versions.join(", ")}" unless versions.empty?
  end
end
