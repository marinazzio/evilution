# frozen_string_literal: true

require "tmpdir"
require "evilution/child_output"

RSpec.describe Evilution::ChildOutput do
  before { described_class.log_dir = nil }
  after  { described_class.log_dir = nil }

  describe ".log_dir / .log_dir=" do
    it "defaults to nil" do
      expect(described_class.log_dir).to be_nil
    end

    it "stores and returns the assigned directory" do
      described_class.log_dir = "/tmp/foo"
      expect(described_class.log_dir).to eq("/tmp/foo")
    end
  end

  describe ".redirect!" do
    it "is a no-op when log_dir is nil" do
      expect { described_class.redirect! }.not_to raise_error
    end

    it "creates the directory if missing and reopens $stdout/$stderr to per-pid files in a forked child" do
      Dir.mktmpdir do |parent_tmp|
        log_dir = File.join(parent_tmp, "children")
        marker = File.join(parent_tmp, "ack")

        pid = Process.fork do
          described_class.log_dir = log_dir
          described_class.redirect!
          warn "stderr-message"
          puts "stdout-message"
          File.write(marker, "ok")
        end
        Process.wait(pid)

        expect(File.read(marker)).to eq("ok")
        expect(File.directory?(log_dir)).to be(true)
        err_file = File.join(log_dir, "#{pid}.err")
        out_file = File.join(log_dir, "#{pid}.out")
        expect(File.read(err_file)).to include("stderr-message")
        expect(File.read(out_file)).to include("stdout-message")
      end
    end
  end
end
