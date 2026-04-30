# frozen_string_literal: true

require "evilution/process_cleanup"

RSpec.describe Evilution::ProcessCleanup do
  def nonexistent_pid
    pid = Process.fork { exit!(0) }
    Process.wait(pid)
    pid
  end

  describe ".safe_kill" do
    it "delegates to Process.kill" do
      pid = Process.fork { sleep 5 }
      described_class.safe_kill("TERM", pid)
      Process.wait(pid)

      expect($CHILD_STATUS.signaled?).to be true
    end

    it "swallows Errno::ESRCH for an unknown pid" do
      expect { described_class.safe_kill("TERM", nonexistent_pid) }.not_to raise_error
    end

    it "returns nil when the process does not exist" do
      expect(described_class.safe_kill("TERM", nonexistent_pid)).to be_nil
    end
  end

  describe ".safe_wait" do
    it "reaps a child process and returns its pid" do
      pid = Process.fork { exit!(0) }

      expect(described_class.safe_wait(pid)).to eq(pid)
    end

    it "swallows Errno::ECHILD when no child to reap" do
      expect { described_class.safe_wait(nonexistent_pid) }.not_to raise_error
    end

    it "returns nil when there is no child" do
      expect(described_class.safe_wait(nonexistent_pid)).to be_nil
    end
  end
end
