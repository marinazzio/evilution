# frozen_string_literal: true

require "evilution/process_cleanup"

RSpec.describe Evilution::ProcessCleanup do
  describe ".safe_kill" do
    it "delegates to Process.kill" do
      pid = Process.fork { sleep 5 }
      described_class.safe_kill("TERM", pid)
      Process.wait(pid)

      expect($CHILD_STATUS.signaled?).to be true
    end

    it "swallows Errno::ESRCH for an unknown pid" do
      allow(Process).to receive(:kill).and_raise(Errno::ESRCH)

      expect { described_class.safe_kill("TERM", 999_999) }.not_to raise_error
    end

    it "returns nil when the process does not exist" do
      allow(Process).to receive(:kill).and_raise(Errno::ESRCH)

      expect(described_class.safe_kill("TERM", 999_999)).to be_nil
    end
  end

  describe ".safe_wait" do
    it "reaps a child process and returns its pid" do
      pid = Process.fork { exit!(0) }

      expect(described_class.safe_wait(pid)).to eq(pid)
    end

    it "swallows Errno::ECHILD when no child to reap" do
      allow(Process).to receive(:wait).and_raise(Errno::ECHILD)

      expect { described_class.safe_wait(999_999) }.not_to raise_error
    end

    it "returns nil when there is no child" do
      allow(Process).to receive(:wait).and_raise(Errno::ECHILD)

      expect(described_class.safe_wait(999_999)).to be_nil
    end
  end
end
