# frozen_string_literal: true

require "spec_helper"
require "timeout"
require "tmpdir"
require "evilution/runner"
require "evilution/config"
require "evilution/isolation/fork"
require "evilution/parallel/work_queue/worker"
require "evilution/parallel/work_queue/worker/loop"

# EV-7a91 / EV-5rrh step 4: end-to-end cross-path lifecycle proof. Both lifecycle
# paths run at once, exactly as under `jobs > 1`:
#
#   session (Runner-equivalent: owns the ProcessSupervisor signal trap)
#     └─ WorkQueue::Worker          (OUTER path, own process group)
#          └─ Isolation::Fork child (INNER path, own process group, EV-2sh8)
#               └─ test_command grandchild (blocking, in the Fork child's group)
#
# A terminal interrupt reaches the session, whose trap forwards a group-kill to
# every worker (ProcessSupervisor.signal_all) and the session exits. The inner
# Fork child left the worker's process group (setpgid, EV-2sh8), so the session's
# kill never reaches it directly -- the worker tears down and reaps the inner
# children it owns via its own INT/TERM handler (ProcessSupervisor
# .kill_and_reap_all, EV-7a91). The reaping mechanism itself is covered
# deterministically by the ProcessSupervisor unit specs; this spec asserts the
# integrated guarantee: after a real interrupt no pid survives on either path.
# Gated on /proc: the spec asserts the absence of running/zombie pids by reading
# /proc/<pid>, so it only runs where /proc is mounted (Linux). Elsewhere the
# pid-state checks are meaningless and would fail spuriously.
RSpec.describe "Cross-path lifecycle under interrupt", if: File.exist?("/proc/self/status") do
  # /proc/<pid> exists while a process is running OR a zombie, and is gone only
  # once the pid is fully reaped -- so a surviving zombie still counts as present.
  def process_exists?(pid)
    File.exist?("/proc/#{pid}")
  end

  def wait_until(condition_timeout: 15)
    Timeout.timeout(condition_timeout) do
      sleep(0.05) until yield
    end
  end

  def reap_quietly(pid)
    Process.waitpid(pid)
  rescue Errno::ECHILD, Errno::ESRCH
    nil
  end

  def kill_quietly(pid)
    Process.kill("KILL", pid)
  rescue Errno::ESRCH
    nil
  end

  it "leaves no surviving pid on the outer or inner path after the session is interrupted" do
    Dir.mktmpdir do |dir|
      worker_pidfile = File.join(dir, "worker.pid")
      inner_pidfile = File.join(dir, "inner.pid")
      grandchild_pidfile = File.join(dir, "grandchild.pid")
      ready = File.join(dir, "ready")

      session = fork do
        # Fresh disposition so the session's trap chains to DEFAULT -- the
        # fatal-signal path that skips work_queue#map's ensure cleanup, exactly
        # as a real terminal interrupt does.
        Signal.trap("TERM", "DEFAULT")
        Evilution::Runner.new(config: Evilution::Config.new(skip_config_file: true))
                         .send(:install_signal_handler, "TERM")

        worker = Evilution::Parallel::WorkQueue::Worker.spawn(worker_index: 0, hooks: nil) do |_item|
          File.write(worker_pidfile, Process.pid.to_s)
          test_command = lambda do |_m|
            grandchild = fork { sleep 120 }
            File.write(grandchild_pidfile, grandchild.to_s)
            File.write(inner_pidfile, Process.pid.to_s)
            sleep 120
            { passed: true }
          end
          Evilution::Isolation::Fork.new.call(mutation: :m, test_command: test_command, timeout: 120)
        end
        worker.send_item(0, :go)
        File.write(ready, "1")
        sleep 120
      end

      worker_pid = inner_pid = grandchild_pid = nil
      begin
        wait_until { File.exist?(ready) }
        wait_until do
          [worker_pidfile, inner_pidfile, grandchild_pidfile].all? { |f| File.exist?(f) && !File.empty?(f) }
        end
        worker_pid = File.read(worker_pidfile).to_i
        inner_pid = File.read(inner_pidfile).to_i
        grandchild_pid = File.read(grandchild_pidfile).to_i

        # Every process on both paths is genuinely up before the interrupt.
        [worker_pid, inner_pid, grandchild_pid].each { |pid| expect(process_exists?(pid)).to be(true) }

        # Interrupt the session; its trap forwards the kill to the worker group
        # and it exits. Reap it so only the descendants remain to check.
        Process.kill("TERM", session)
        reap_quietly(session)

        # No pid on either path may survive the interrupt -- the worker reaps its
        # inner child, the inner child's group-kill sweeps the grandchild, and
        # the worker subtree is collected once the session is gone.
        wait_until { [worker_pid, inner_pid, grandchild_pid].none? { |pid| process_exists?(pid) } }
        expect(process_exists?(worker_pid)).to be(false)
        expect(process_exists?(inner_pid)).to be(false)
        expect(process_exists?(grandchild_pid)).to be(false)
      ensure
        [worker_pid, inner_pid, grandchild_pid, session].compact.each do |pid|
          kill_quietly(pid)
          reap_quietly(pid)
        end
      end
    end
  end
end
