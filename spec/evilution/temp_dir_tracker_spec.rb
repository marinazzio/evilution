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
  end
end
