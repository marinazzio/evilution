# frozen_string_literal: true

require "fileutils"
require_relative "../worker_database"

# Copies a SQLite database for one parallel worker.
#
# The copy goes through SQLite's online backup API rather than a file copy: it
# is a consistent snapshot that includes what the write-ahead log holds but has
# not yet been checkpointed into the main file, and it is compact, so a large
# leftover WAL file is not duplicated for every worker. The sqlite3 gem is the
# one the app's SQLite adapter already depends on.
module Evilution::WorkerDatabase::SqliteCopy
  class Incomplete < StandardError; end

  # Files SQLite keeps beside a database. A copy left at the destination by an
  # earlier worker must not lend its log or journal to the new one.
  COMPANIONS = ["", "-wal", "-shm", "-journal"].freeze

  module_function

  # A SQLite database in a plain file. An in-memory database is never shared
  # between processes, and a file: URI carries parameters a copy could not keep.
  def copyable?(configuration_hash)
    database = configuration_hash[:database]
    configuration_hash[:adapter].to_s.include?("sqlite") && database.is_a?(String) && !database.empty? &&
      database != ":memory:" && !database.start_with?("file:")
  end

  def call(source, destination)
    raise Errno::ENOENT, source unless File.file?(source)

    require "sqlite3" unless defined?(::SQLite3::Backup)
    FileUtils.mkdir_p(File.dirname(destination))
    COMPANIONS.each { |suffix| FileUtils.rm_f("#{destination}#{suffix}") }
    backup(source, destination)
  end

  def backup(source, destination)
    from = ::SQLite3::Database.new(source, readonly: true)
    begin
      to = ::SQLite3::Database.new(destination)
      begin
        copy_pages(from, to, source)
      ensure
        to.close
      end
    ensure
      from.close
    end
  end

  def copy_pages(from, to, source)
    backup = ::SQLite3::Backup.new(to, "main", from, "main")
    begin
      status = backup.step(-1)
    ensure
      backup.finish
    end
    return if status == ::SQLite3::Constants::ErrorCode::DONE

    raise Incomplete, "copying #{source} stopped with SQLite status #{status}"
  end
  private_class_method :backup, :copy_pages
end
