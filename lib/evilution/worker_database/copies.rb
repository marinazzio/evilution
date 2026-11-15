# frozen_string_literal: true

require "fileutils"
require "securerandom"
require "tmpdir"
require_relative "../worker_database"

# Where the workers of one parallel pass keep their own copies of the shared
# SQLite test database: a directory under the system temp dir, chosen by the
# parent before the workers fork, with a subdirectory per worker process, so a
# worker that replaces a dead one never opens what the dead one left. Nothing
# is created until a worker copies.
#
# The parent deletes a worker's copies once that worker has been reaped,
# before its replacement starts, so a pass that replaces workers often never
# holds more copies than it has worker slots. It removes the directory when
# the pass ends, also when it ends on an exception or an interrupt. Only a
# parent killed outright (SIGKILL) leaves it behind, in the temp dir. It is
# deliberately not registered with TempDirTracker: a forked child that dies
# runs the inherited at_exit cleanup, which would delete the databases the
# other workers are still using.
class Evilution::WorkerDatabase::Copies
  # Copies are off: every worker keeps the database the preload connected to.
  class None
    def enabled?
      false
    end

    def discard(_pid)
      nil
    end

    def remove
      nil
    end
  end

  NONE = None.new.freeze

  attr_reader :root

  def initialize(root: File.join(Dir.tmpdir, "evilution-worker-db-#{Process.pid}-#{SecureRandom.hex(4)}"))
    @root = root
  end

  def enabled?
    true
  end

  # Runs in the worker: copies the database into this process's directory and
  # returns the copy's path.
  def provision(source)
    destination = File.join(worker_dir(Process.pid), File.basename(source))
    Evilution::WorkerDatabase::SqliteCopy.call(source, destination)
    destination
  end

  # Runs in the parent, once the worker process `pid` has exited: nothing
  # holds its copies open any more.
  def discard(pid)
    FileUtils.rm_rf(worker_dir(pid))
  end

  def remove
    FileUtils.rm_rf(root)
  end

  private

  def worker_dir(pid)
    File.join(root, "worker-#{pid}")
  end
end
