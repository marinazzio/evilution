# frozen_string_literal: true

require "evilution/runner"
require "evilution/rails_detector"
require "fileutils"
require "tmpdir"

RSpec.describe Evilution::Runner, "preload" do
  around do |example|
    Dir.mktmpdir("evilution-runner-preload") do |tmp|
      @tmp = tmp
      Evilution::RailsDetector.reset_cache!
      example.run
    end
  end

  def write_rails_tree(preload_body: nil)
    FileUtils.mkdir_p(File.join(@tmp, "config"))
    FileUtils.mkdir_p(File.join(@tmp, "app", "models"))
    FileUtils.mkdir_p(File.join(@tmp, "spec"))
    File.write(File.join(@tmp, "config", "application.rb"), "# Rails\n")
    File.write(File.join(@tmp, "app", "models", "user.rb"), "class User; end\n")
    body = preload_body || "module EvilutionPreloadFixture; LOADED = true; end"
    File.write(File.join(@tmp, "spec", "rails_helper.rb"), "#{body}\n")
  end

  def build_config(**overrides)
    Evilution::Config.new(
      target_files: [File.join(@tmp, "app", "models", "user.rb")],
      format: :json,
      timeout: 5,
      quiet: true,
      baseline: false,
      isolation: :auto,
      skip_config_file: true,
      **overrides
    )
  end

  describe "Config#preload" do
    it "defaults to nil (auto-detect)" do
      expect(build_config.preload).to be_nil
    end

    it "accepts an explicit path as a String" do
      expect(build_config(preload: "custom/path.rb").preload).to eq("custom/path.rb")
    end

    it "accepts false to disable preload" do
      expect(build_config(preload: false).preload).to be(false)
    end

    it "rejects unsupported types" do
      expect { build_config(preload: 42) }.to raise_error(Evilution::ConfigError, /preload/)
    end
  end

  describe "#perform_preload" do
    it "requires spec/rails_helper.rb when isolation resolves to fork and Rails is detected" do
      write_rails_tree
      runner = described_class.new(config: build_config)
      runner.send(:perform_preload)
      expect(defined?(EvilutionPreloadFixture::LOADED)).to eq("constant")
    ensure
      Object.send(:remove_const, :EvilutionPreloadFixture) if defined?(EvilutionPreloadFixture)
    end

    it "is a no-op when preload is false" do
      write_rails_tree(preload_body: 'raise "should not be loaded"')
      runner = described_class.new(config: build_config(preload: false))
      expect { runner.send(:perform_preload) }.not_to raise_error
    end

    it "is a no-op when isolation resolves to :in_process" do
      write_rails_tree(preload_body: 'raise "should not be loaded"')
      # Explicit :in_process on Rails — user accepted the warning, no preload
      runner = described_class.new(
        config: build_config(isolation: :in_process, quiet: true)
      )
      expect { runner.send(:perform_preload) }.not_to raise_error
    end

    it "is a no-op on a non-Rails project" do
      FileUtils.mkdir_p(File.join(@tmp, "lib"))
      File.write(File.join(@tmp, "lib", "thing.rb"), "class Thing; end\n")
      runner = described_class.new(
        config: build_config(target_files: [File.join(@tmp, "lib", "thing.rb")])
      )
      expect { runner.send(:perform_preload) }.not_to raise_error
    end

    it "honors an explicit preload path" do
      FileUtils.mkdir_p(File.join(@tmp, "custom"))
      File.write(
        File.join(@tmp, "custom", "bootstrap.rb"),
        "module EvilutionPreloadFixtureCustom; LOADED = true; end"
      )
      write_rails_tree(preload_body: 'raise "default should not be loaded"')
      runner = described_class.new(
        config: build_config(preload: File.join(@tmp, "custom", "bootstrap.rb"))
      )
      runner.send(:perform_preload)
      expect(defined?(EvilutionPreloadFixtureCustom::LOADED)).to eq("constant")
    ensure
      Object.send(:remove_const, :EvilutionPreloadFixtureCustom) if defined?(EvilutionPreloadFixtureCustom)
    end

    it "raises ConfigError when the preload file exists but raises on load" do
      write_rails_tree(preload_body: 'raise "boom in preload"')
      runner = described_class.new(config: build_config)
      expect { runner.send(:perform_preload) }.to raise_error(Evilution::ConfigError, /preload/)
    end

    it "raises ConfigError when an explicit preload path does not exist" do
      write_rails_tree
      runner = described_class.new(
        config: build_config(preload: File.join(@tmp, "does_not_exist.rb"))
      )
      expect { runner.send(:perform_preload) }.to raise_error(Evilution::ConfigError, /preload/)
    end
  end
end
