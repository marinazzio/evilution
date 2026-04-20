# frozen_string_literal: true

require "evilution/temp_dir_tracker"

RSpec.describe Evilution::TempDirTracker do
  after do
    described_class.cleanup_all
  end

  describe ".register and .unregister" do
    it "tracks a temp directory" do
      dir = Dir.mktmpdir("evilution_test")

      described_class.register(dir)

      expect(described_class.tracked_dirs).to include(dir)
    ensure
      FileUtils.rm_rf(dir)
    end

    it "unregisters a temp directory" do
      dir = Dir.mktmpdir("evilution_test")
      described_class.register(dir)

      described_class.unregister(dir)

      expect(described_class.tracked_dirs).not_to include(dir)
    ensure
      FileUtils.rm_rf(dir)
    end
  end

  describe ".cleanup_all" do
    it "removes all tracked temp directories" do
      dirs = Array.new(3) { Dir.mktmpdir("evilution_test") }
      dirs.each { |d| described_class.register(d) }

      described_class.cleanup_all

      dirs.each { |d| expect(Dir.exist?(d)).to be false }
    end

    it "clears the tracked set after cleanup" do
      dir = Dir.mktmpdir("evilution_test")
      described_class.register(dir)

      described_class.cleanup_all

      expect(described_class.tracked_dirs).to be_empty
    end

    it "handles already-removed directories gracefully" do
      dir = Dir.mktmpdir("evilution_test")
      described_class.register(dir)
      FileUtils.rm_rf(dir)

      expect { described_class.cleanup_all }.not_to raise_error
    end

    it "is safe to invoke from a Signal.trap handler (no ThreadError)" do
      require "timeout"

      dir = Dir.mktmpdir("evilution_test")
      described_class.register(dir)
      queue = Queue.new
      previous = Signal.trap("USR1") do
        described_class.cleanup_all
        queue << :done
      rescue StandardError => e
        queue << e
      end

      result = begin
        Process.kill("USR1", Process.pid)
        Timeout.timeout(2) { queue.pop }
      ensure
        Signal.trap("USR1", previous || "DEFAULT")
      end

      expect(result).to eq(:done)
      expect(Dir.exist?(dir)).to be false
    end

    it "keeps a directory tracked when FileUtils.rm_rf raises" do
      dir = Dir.mktmpdir("evilution_test")
      described_class.register(dir)
      call_count = 0
      allow(FileUtils).to receive(:rm_rf).with(dir).and_wrap_original do |orig, arg|
        call_count += 1
        raise StandardError, "boom" if call_count == 1

        orig.call(arg)
      end

      described_class.cleanup_all

      expect(described_class.tracked_dirs).to include(dir)
    ensure
      described_class.cleanup_all if dir
    end
  end
end
