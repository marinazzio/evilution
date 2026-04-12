# frozen_string_literal: true

require "spec_helper"
require "fileutils"
require "tmpdir"
require "evilution/rails_detector"

RSpec.describe Evilution::RailsDetector do
  around do |example|
    Dir.mktmpdir("evilution-rails-detector") do |tmp|
      @tmp = tmp
      described_class.reset_cache!
      example.run
    end
  end

  def rails_tree
    FileUtils.mkdir_p(File.join(@tmp, "config"))
    FileUtils.mkdir_p(File.join(@tmp, "app", "models"))
    File.write(File.join(@tmp, "config", "application.rb"), "# Rails app\n")
    File.write(File.join(@tmp, "app", "models", "user.rb"), "class User; end\n")
  end

  def non_rails_tree
    FileUtils.mkdir_p(File.join(@tmp, "lib"))
    File.write(File.join(@tmp, "lib", "thing.rb"), "class Thing; end\n")
  end

  describe ".rails_root_for" do
    it "returns the Rails root when the path lives under one" do
      rails_tree
      result = described_class.rails_root_for(File.join(@tmp, "app", "models", "user.rb"))
      expect(result).to eq(@tmp)
    end

    it "returns nil when no config/application.rb exists up the tree" do
      non_rails_tree
      expect(described_class.rails_root_for(File.join(@tmp, "lib", "thing.rb"))).to be_nil
    end

    it "returns nil for a non-existent path" do
      expect(described_class.rails_root_for(File.join(@tmp, "does_not_exist.rb"))).to be_nil
    end

    it "memoizes the walk-up result for the same directory" do
      rails_tree
      path = File.join(@tmp, "app", "models", "user.rb")
      described_class.rails_root_for(path)
      # Remove the marker; memoized result should still return
      FileUtils.rm_f(File.join(@tmp, "config", "application.rb"))
      expect(described_class.rails_root_for(path)).to eq(@tmp)
    end

    it "stops at the filesystem root without error" do
      FileUtils.mkdir_p(File.join(@tmp, "a", "b"))
      File.write(File.join(@tmp, "a", "b", "x.rb"), "")
      expect(described_class.rails_root_for(File.join(@tmp, "a", "b", "x.rb"))).to be_nil
    end
  end

  describe ".rails_root_for_any" do
    it "returns the first detected root among a list of paths" do
      rails_tree
      described_class.reset_cache!
      paths = [
        File.join(@tmp, "nowhere.rb"),
        File.join(@tmp, "app", "models", "user.rb")
      ]
      expect(described_class.rails_root_for_any(paths)).to eq(@tmp)
    end

    it "returns nil when no path is under a Rails root" do
      non_rails_tree
      expect(described_class.rails_root_for_any([File.join(@tmp, "lib", "thing.rb")])).to be_nil
    end

    it "returns nil for an empty list" do
      expect(described_class.rails_root_for_any([])).to be_nil
    end
  end
end
