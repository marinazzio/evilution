# frozen_string_literal: true

require "spec_helper"
require "timeout"
require "tmpdir"
require "evilution/runner"
require "evilution/parallel/work_queue/worker"
require "evilution/parallel/work_queue/worker/loop"
require "evilution/parallel/work_queue/worker_registry"

# EV-jwao / GH #1332: end-to-end proof that a terminal interrupt is forwarded to
# worker process groups so an actively-busy worker (and the grandchildren it
# forked) does not leak when the parent dies via the fatal-signal path that
# skips work_queue#map's `ensure cleanup_workers`.
RSpec.describe "Interrupt forwarding to busy worker groups" do
  def process_alive?(pid)
    Process.kill(0, pid)
    true
  rescue Errno::ESRCH
    false
  rescue Errno::EPERM
    true
  end

  def wait_until(timeout: 8)
    Timeout.timeout(timeout) do
      sleep(0.05) until yield
    end
  end

  it "kills the busy worker subtree when the parent is interrupted" do
    Dir.mktmpdir do |dir|
      ready_file = File.join(dir, "ready")
      gpid_file = File.join(dir, "grandchild.pid")
      gpid = nil

      parent_pid = fork do
        # Fresh signal disposition so install_signal_handler chains to DEFAULT
        # (the fatal-signal path that skips the ensure cleanup).
        Signal.trap("TERM", "DEFAULT")
        Evilution::Runner.new(config: Evilution::Config.new(skip_config_file: true))
                         .send(:install_signal_handler, "TERM")

        worker = Evilution::Parallel::WorkQueue::Worker.spawn(worker_index: 0, hooks: nil) do |_item|
          grandchild = fork { sleep 60 }
          File.write(gpid_file, grandchild.to_s)
          sleep 60
        end
        worker.send_item(0, :go)

        File.write(ready_file, "1")
        sleep 60
      end

      begin
        wait_until { File.exist?(ready_file) }
        wait_until { File.exist?(gpid_file) && !File.empty?(gpid_file) }
        gpid = File.read(gpid_file).to_i
        expect(process_alive?(gpid)).to be(true)

        Process.kill("TERM", parent_pid)

        status =
          begin
            Timeout.timeout(8) { Process.wait2(parent_pid).last }
          rescue Timeout::Error
            Process.kill("KILL", parent_pid)
            Process.wait2(parent_pid).last
          end
        expect(status.signaled?).to be(true)

        # The grandchild was in the worker's forwarded group, so it must be gone.
        wait_until { !process_alive?(gpid) }
        expect(process_alive?(gpid)).to be(false)
      ensure
        begin
          Process.kill("KILL", gpid) if gpid && process_alive?(gpid)
        rescue Errno::ESRCH
          nil
        end
      end
    end
  end
end
