# frozen_string_literal: true

require "fileutils"
require_relative "version"
require_relative "temp_dir_tracker"

# Single owner of the process-lifecycle invariant: every pid spawned here is
# group-isolated, tracked in a signal-safe registry, group-signalled through a
# TERM/KILL ladder, and reaped -- with its fds closed and sandbox dir removed.
#
# EV-9f3b / EV-5rrh, Track A step 1. Generalizes the lock-free COW
# WorkerRegistry (EV-jwao) and absorbs ProcessCleanup.safe_kill/safe_wait
# semantics. Pure unit: no call sites are migrated here -- Isolation::Fork
# (inner path) and WorkQueue::Worker (outer path) are routed through it in
# later steps (EV-3aw3, EV-dg69, EV-7a91).
#
# Shape: instances own the lifecycle of the children they spawn, but every
# handle is also recorded in ONE process-global registry so the Runner signal
# trap can `.signal_all` across every fork-site through a single owner.
#
# Signal-safety: under MRI a trap handler runs on the main thread between VM
# instructions, so it must not acquire a Mutex (the main thread may hold it ->
# deadlock). register/unregister swap @registry for a freshly built frozen
# array via a single atomic reference assignment (copy-on-write). The trap
# reads the current reference once and iterates that complete, immutable
# snapshot -- no torn reads, no lock.
class Evilution::ProcessSupervisor
  GRACE_PERIOD = 2

  # One tracked child: leader pid, its process-group id (== pid for a group
  # leader), the parent-side fds to close on reap, and an optional sandbox dir
  # to remove on reap.
  Handle = Struct.new(:pid, :pgid, :fds, :sandbox_dir, keyword_init: true)

  @registry = [].freeze

  class << self
    # Frozen snapshot. Safe to read from a signal handler.
    attr_reader :registry

    def register(handle)
      @registry = (@registry + [handle]).freeze
    end

    def unregister(handle)
      @registry = @registry.reject { |existing| existing.pid == handle.pid }.freeze
    end

    def signal_all(sig)
      @registry.each do |handle|
        Process.kill(sig, -handle.pgid)
      rescue Errno::ESRCH
        # Group already gone (leader + subtree reaped) -- nothing to signal.
        nil
      end
    end
  end

  # Fork a child that becomes its own process-group leader and runs the block,
  # returning a Handle. The child calls setpgid(0, 0) before yielding so any
  # grandchildren it forks join its group and can be swept by a group signal;
  # the parent repeats setpgid(pid, pid) to close the race where it signals
  # before the child has isolated itself. The handle is registered BEFORE the
  # parent-side setpgid so the trap can never observe a child that is already a
  # group leader yet missing from the registry (EV-jwao race).
  def spawn(sandbox_dir: nil, fds: [])
    pid = ::Process.fork do
      isolate_self
      yield
    end

    # Track the sandbox first thing after fork: if the parent takes a fatal
    # signal before isolate_child returns, Runner's trap (TempDirTracker
    # .cleanup_all) can still see and remove it, narrowing the leak window.
    Evilution::TempDirTracker.register(sandbox_dir) if sandbox_dir
    handle = Handle.new(pid: pid, pgid: pid, fds: fds, sandbox_dir: sandbox_dir)
    self.class.register(handle)
    isolate_child(pid)
    handle
  end

  # Signal the child's whole process group (-pgid) to sweep any grandchildren,
  # then the bare pid as a fallback for the case where setpgid failed (no group
  # exists, so the group signal is a harmless Errno::ESRCH).
  def signal_group(sig, handle)
    safe_kill(sig, -handle.pgid)
    safe_kill(sig, handle.pid)
  end

  # Bounded TERM -> grace -> KILL ladder, then reap. Always ends with the child
  # reaped and its resources released, whichever rung it dies on.
  def terminate(handle, grace: GRACE_PERIOD)
    signal_group("TERM", handle)
    unless exited?(handle.pid)
      sleep(grace)
      signal_group("KILL", handle) unless exited?(handle.pid)
    end
    reap(handle)
  end

  # Reap the leader (ECHILD-tolerant if already reaped), then unconditionally
  # release the resources the handle owns: close parent-side fds, remove the
  # sandbox dir, and drop the handle from the registry.
  def reap(handle)
    safe_wait(handle.pid)
  ensure
    close_fds(handle)
    cleanup_sandbox(handle)
    self.class.unregister(handle)
  end

  private

  def isolate_self
    ::Process.setpgid(0, 0)
  rescue SystemCallError
    nil
  end

  def isolate_child(pid)
    ::Process.setpgid(pid, pid)
  rescue Errno::EACCES, Errno::ESRCH
    # EACCES: child already exec'd; ESRCH: child already exited.
    nil
  end

  # True once the child has been reaped (now or earlier). WNOHANG returns the
  # pid for a freshly exited child, nil while it still runs, and raises ECHILD
  # if it was already reaped -- all of which we treat as "no longer running".
  def exited?(pid)
    !::Process.waitpid(pid, ::Process::WNOHANG).nil?
  rescue Errno::ECHILD
    true
  end

  def safe_kill(signal, target)
    ::Process.kill(signal, target)
  rescue Errno::ESRCH
    nil
  end

  def safe_wait(pid)
    ::Process.wait(pid)
  rescue Errno::ECHILD
    nil
  end

  def close_fds(handle)
    handle.fds.each do |io|
      io.close unless io.closed?
    rescue IOError
      nil
    end
  end

  # Remove the sandbox first, then drop it from TempDirTracker only on success.
  # If removal raises, leave the dir tracked so TempDirTracker.cleanup_all /
  # at_exit can retry it, and swallow the error so reap's ensure-path still
  # unregisters the handle (no stale entry in the process-global registry).
  def cleanup_sandbox(handle)
    dir = handle.sandbox_dir
    return unless dir

    FileUtils.rm_rf(dir)
    Evilution::TempDirTracker.unregister(dir)
  rescue StandardError
    nil
  end
end
