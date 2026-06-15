# frozen_string_literal: true

require "spec_helper"
require "timeout"
require "tmpdir"
require "evilution/process_supervisor"

RSpec.describe Evilution::ProcessSupervisor do
  # Isolate the process-global registry around every example so a leaked or
  # pre-existing handle from elsewhere never bleeds into these assertions.
  around do |example|
    snapshot = described_class.registry
    snapshot.each { |h| described_class.unregister(h) }
    example.run
    described_class.registry.each { |h| described_class.unregister(h) }
    snapshot.each { |h| described_class.register(h) }
  end

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

  def handle(pid: 4242, pgid: 4242, fds: [], sandbox_dir: nil)
    described_class::Handle.new(pid: pid, pgid: pgid, fds: fds, sandbox_dir: sandbox_dir)
  end

  describe "Handle" do
    it "carries pid, pgid, fds and sandbox_dir" do
      h = handle(pid: 1, pgid: 2, fds: [:io], sandbox_dir: "/tmp/x")
      expect([h.pid, h.pgid, h.fds, h.sandbox_dir]).to eq([1, 2, [:io], "/tmp/x"])
    end
  end

  describe ".register / .registry" do
    it "starts empty in an isolated registry" do
      expect(described_class.registry).to eq([])
    end

    it "records a registered handle" do
      h = handle
      described_class.register(h)
      expect(described_class.registry).to contain_exactly(h)
    end

    it "records multiple handles in registration order" do
      a = handle(pid: 10, pgid: 10)
      b = handle(pid: 20, pgid: 20)
      described_class.register(a)
      described_class.register(b)
      expect(described_class.registry).to eq([a, b])
    end

    it "exposes the registry as a frozen snapshot" do
      described_class.register(handle)
      expect(described_class.registry).to be_frozen
    end

    it "returns an independent snapshot that later registrations do not mutate" do
      described_class.register(handle(pid: 1, pgid: 1))
      snapshot = described_class.registry
      described_class.register(handle(pid: 2, pgid: 2))
      expect(snapshot.map(&:pid)).to eq([1])
    end
  end

  describe ".unregister" do
    it "removes a registered handle by pid" do
      a = handle(pid: 7, pgid: 7)
      b = handle(pid: 8, pgid: 8)
      described_class.register(a)
      described_class.register(b)
      described_class.unregister(a)
      expect(described_class.registry).to contain_exactly(b)
    end

    it "is a no-op when the handle was never registered" do
      described_class.register(handle(pid: 5, pgid: 5))
      expect { described_class.unregister(handle(pid: 999, pgid: 999)) }
        .not_to change(described_class, :registry)
    end
  end

  describe ".signal_all" do
    it "sends the signal to the negated pgid of every registered group" do
      allow(Process).to receive(:kill)
      described_class.register(handle(pid: 11, pgid: 11))
      described_class.register(handle(pid: 22, pgid: 22))

      described_class.signal_all("TERM")

      expect(Process).to have_received(:kill).with("TERM", -11)
      expect(Process).to have_received(:kill).with("TERM", -22)
    end

    it "swallows Errno::ESRCH for an already-dead group and continues" do
      allow(Process).to receive(:kill).with("INT", -1).and_raise(Errno::ESRCH)
      allow(Process).to receive(:kill).with("INT", -2)
      described_class.register(handle(pid: 1, pgid: 1))
      described_class.register(handle(pid: 2, pgid: 2))

      expect { described_class.signal_all("INT") }.not_to raise_error
      expect(Process).to have_received(:kill).with("INT", -2)
    end

    it "does nothing when nothing is registered" do
      allow(Process).to receive(:kill)
      described_class.signal_all("INT")
      expect(Process).not_to have_received(:kill)
    end
  end

  describe "#spawn" do
    subject(:supervisor) { described_class.new }

    it "forks a child that runs the block and makes it its own group leader" do
      h = supervisor.spawn { sleep 60 }
      begin
        expect(h.pid).to be_a(Integer)
        expect(h.pgid).to eq(h.pid)
        expect(process_alive?(h.pid)).to be(true)
        expect(Process.getpgid(h.pid)).to eq(h.pid)
      ensure
        supervisor.terminate(h, grace: 0.2)
      end
    end

    it "registers the spawned handle in the process-global registry" do
      h = supervisor.spawn { sleep 60 }
      begin
        expect(described_class.registry).to include(h)
      ensure
        supervisor.terminate(h, grace: 0.2)
      end
    end

    it "isolates the child into its own group from the child side by default" do
      # Neutralize the parent-side setpgid so only child-side isolation can
      # make the child a group leader.
      allow(supervisor).to receive(:isolate_child)
      reader, writer = IO.pipe
      h = supervisor.spawn do
        writer.write(Process.getpgrp.to_s)
        writer.close
        sleep 60
      end
      begin
        writer.close
        expect(Integer(reader.read)).to eq(h.pid)
      ensure
        reader.close
        supervisor.terminate(h, grace: 0.2)
      end
    end

    it "leaves the child in the parent group when isolate_in_child is false" do
      # Neutralize parent-side setpgid too, so the child can only be isolated if
      # it self-isolates -- which it must not when isolate_in_child is false.
      allow(supervisor).to receive(:isolate_child)
      reader, writer = IO.pipe
      h = supervisor.spawn(isolate_in_child: false) do
        writer.write(Process.getpgrp.to_s)
        writer.close
        sleep 60
      end
      begin
        writer.close
        child_pgrp = Integer(reader.read)
        expect(child_pgrp).to eq(Process.getpgrp)
        expect(child_pgrp).not_to eq(h.pid)
      ensure
        reader.close
        supervisor.terminate(h, grace: 0.2)
      end
    end

    it "registers the handle before isolating the child (no leader-but-unregistered window)" do
      registry_size_at_isolate = nil
      allow(supervisor).to receive(:isolate_child) do |_pid|
        registry_size_at_isolate = described_class.registry.size
      end
      h = supervisor.spawn(isolate_in_child: false) { sleep 60 }
      begin
        expect(registry_size_at_isolate).to eq(1)
      ensure
        supervisor.terminate(h, grace: 0.2)
      end
    end

    it "tolerates a benign parent-side setpgid failure (ESRCH) without warning" do
      allow(supervisor).to receive(:warn)
      allow(Process).to receive(:setpgid).and_raise(Errno::ESRCH)
      h = supervisor.spawn(isolate_in_child: false) { sleep 60 }
      begin
        expect(supervisor).not_to have_received(:warn)
      ensure
        allow(Process).to receive(:setpgid).and_call_original
        supervisor.terminate(h, grace: 0.2)
      end
    end

    it "warns but does not raise when parent-side isolation fails unexpectedly" do
      allow(supervisor).to receive(:warn)
      allow(Process).to receive(:setpgid).and_raise(Errno::EPERM)
      h = nil
      begin
        expect { h = supervisor.spawn(isolate_in_child: false) { sleep 60 } }.not_to raise_error
        expect(supervisor).to have_received(:warn).with(/could not isolate/)
      ensure
        allow(Process).to receive(:setpgid).and_call_original
        supervisor.terminate(h, grace: 0.2) if h
      end
    end

    it "registers the sandbox dir with TempDirTracker" do
      Dir.mktmpdir("supervisor-spawn") do |dir|
        sandbox = File.join(dir, "box")
        Dir.mkdir(sandbox)
        h = supervisor.spawn(sandbox_dir: sandbox) { sleep 60 }
        begin
          expect(Evilution::TempDirTracker.tracked_dirs).to include(sandbox)
        ensure
          supervisor.terminate(h, grace: 0.2)
        end
      end
    end
  end

  describe "#signal_group" do
    subject(:supervisor) { described_class.new }

    it "signals the negated pgid then the bare pid as a fallback" do
      allow(Process).to receive(:kill)
      supervisor.signal_group("TERM", handle(pid: 33, pgid: 33))

      expect(Process).to have_received(:kill).with("TERM", -33)
      expect(Process).to have_received(:kill).with("TERM", 33)
    end

    it "swallows Errno::ESRCH from a dead group or pid" do
      allow(Process).to receive(:kill).and_raise(Errno::ESRCH)
      expect { supervisor.signal_group("KILL", handle(pid: 44, pgid: 44)) }
        .not_to raise_error
    end
  end

  describe "#terminate" do
    subject(:supervisor) { described_class.new }

    it "kills the whole group, sweeping grandchildren, and reaps the leader" do
      Dir.mktmpdir do |dir|
        pidfile = File.join(dir, "grandchild.pid")
        gpid = nil
        h = supervisor.spawn do
          grandchild = fork { sleep 60 }
          File.write(pidfile, grandchild.to_s)
          sleep 60
        end
        begin
          wait_until { File.exist?(pidfile) && !File.empty?(pidfile) }
          gpid = File.read(pidfile).to_i
          expect(process_alive?(gpid)).to be(true)

          supervisor.terminate(h, grace: 0.2)

          wait_until { !process_alive?(h.pid) }
          wait_until { !process_alive?(gpid) }
          expect(process_alive?(h.pid)).to be(false)
          expect(process_alive?(gpid)).to be(false)
        ensure
          [h.pid, gpid].compact.each do |pid|
            Process.kill("KILL", pid)
          rescue Errno::ESRCH
            nil
          end
        end
      end
    end

    it "escalates to KILL when the child ignores TERM" do
      h = supervisor.spawn do
        Signal.trap("TERM", "IGNORE")
        sleep 60
      end
      begin
        # Give the child a moment to install the TERM trap.
        sleep 0.2
        supervisor.terminate(h, grace: 0.3)
        wait_until { !process_alive?(h.pid) }
        expect(process_alive?(h.pid)).to be(false)
      ensure
        begin
          Process.kill("KILL", h.pid)
        rescue Errno::ESRCH
          nil
        end
      end
    end

    it "unregisters the handle once reaped" do
      h = supervisor.spawn { sleep 60 }
      supervisor.terminate(h, grace: 0.2)
      expect(described_class.registry).not_to include(h)
    end
  end

  describe "#reap" do
    subject(:supervisor) { described_class.new }

    it "waits for the child, closes its fds, and removes the sandbox dir" do
      sandbox = Dir.mktmpdir("supervisor-reap")
      read_io, write_io = IO.pipe
      h = supervisor.spawn(fds: [read_io, write_io], sandbox_dir: sandbox) { exit!(0) }

      supervisor.reap(h)

      expect(read_io).to be_closed
      expect(write_io).to be_closed
      expect(Dir.exist?(sandbox)).to be(false)
      expect(Evilution::TempDirTracker.tracked_dirs).not_to include(sandbox)
      expect(described_class.registry).not_to include(h)
    end

    it "tolerates ECHILD when the child was already reaped" do
      h = supervisor.spawn { exit!(0) }
      supervisor.reap(h)
      expect { supervisor.reap(h) }.not_to raise_error
    end
  end

  describe "#reap_nonblock" do
    subject(:supervisor) { described_class.new }

    it "returns false and keeps the handle registered while the child runs" do
      h = supervisor.spawn { sleep 60 }
      begin
        expect(supervisor.reap_nonblock(h)).to be(false)
        expect(described_class.registry).to include(h)
      ensure
        supervisor.terminate(h, grace: 0.2)
      end
    end

    it "reaps an exited child, releases it, and drops it from the registry" do
      sandbox = Dir.mktmpdir("supervisor-reap-nonblock")
      read_io, write_io = IO.pipe
      h = supervisor.spawn(fds: [read_io, write_io], sandbox_dir: sandbox) { exit!(0) }

      wait_until { supervisor.reap_nonblock(h) }

      expect(read_io).to be_closed
      expect(write_io).to be_closed
      expect(Dir.exist?(sandbox)).to be(false)
      expect(Evilution::TempDirTracker.tracked_dirs).not_to include(sandbox)
      expect(described_class.registry).not_to include(h)
    end

    it "tolerates ECHILD and returns true when already reaped" do
      h = supervisor.spawn { exit!(0) }
      wait_until { supervisor.reap_nonblock(h) }
      expect(supervisor.reap_nonblock(h)).to be(true)
    end

    it "still unregisters the handle and does not raise when sandbox removal fails" do
      Dir.mktmpdir("supervisor-reap-fail") do |outer|
        sandbox = File.join(outer, "box")
        Dir.mkdir(sandbox)
        h = supervisor.spawn(sandbox_dir: sandbox) { exit!(0) }

        allow(FileUtils).to receive(:rm_rf).and_call_original
        allow(FileUtils).to receive(:rm_rf).with(sandbox).and_raise(Errno::EACCES)

        expect { supervisor.reap(h) }.not_to raise_error
        expect(described_class.registry).not_to include(h)
        # Dir left tracked so a later TempDirTracker.cleanup_all can retry.
        expect(Evilution::TempDirTracker.tracked_dirs).to include(sandbox)
      end
    end
  end
end
