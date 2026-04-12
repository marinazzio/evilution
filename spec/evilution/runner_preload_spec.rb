# frozen_string_literal: true

require "English"
require "evilution/runner"
require "evilution/rails_detector"
require "fileutils"
require "tmpdir"

RSpec.describe Evilution::Runner, "preload" do
  around do |example|
    Dir.mktmpdir("evilution-runner-preload") do |tmp|
      @tmp = tmp
      saved_load_path = $LOAD_PATH.dup
      Evilution::RailsDetector.reset_cache!
      example.run
      $LOAD_PATH.replace(saved_load_path)
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

    it "raises ConfigError when the preload file has a SyntaxError" do
      write_rails_tree(preload_body: "def broken(")
      runner = described_class.new(config: build_config)
      expect { runner.send(:perform_preload) }.to raise_error(Evilution::ConfigError, /preload/)
    end

    it "adds spec/ to $LOAD_PATH so rails_helper can require spec_helper" do
      write_rails_tree
      unique = "evilution_preload_lp_#{$PROCESS_ID}"
      File.write(
        File.join(@tmp, "spec", "#{unique}.rb"),
        "module EvilutionPreloadLP; LOADED = true; end\n"
      )
      File.write(
        File.join(@tmp, "spec", "rails_helper.rb"),
        "require '#{unique}'\nmodule EvilutionPreloadMain; LOADED = true; end\n"
      )

      original_lp = $LOAD_PATH.dup
      runner = described_class.new(config: build_config)
      runner.send(:perform_preload)

      expect(defined?(EvilutionPreloadLP::LOADED)).to eq("constant")
      expect(defined?(EvilutionPreloadMain::LOADED)).to eq("constant")
    ensure
      $LOAD_PATH.replace(original_lp) if original_lp
      $LOADED_FEATURES.delete_if { |f| f.include?(unique) } if unique
      Object.send(:remove_const, :EvilutionPreloadLP) if defined?(EvilutionPreloadLP)
      Object.send(:remove_const, :EvilutionPreloadMain) if defined?(EvilutionPreloadMain)
    end

    it "requires rspec/core before the preload file" do
      write_rails_tree
      runner = described_class.new(config: build_config)

      load_order = []
      allow(runner).to receive(:require).and_wrap_original do |original, path|
        load_order << path
        original.call(path)
      end

      runner.send(:perform_preload)

      rspec_idx = load_order.index("rspec/core")
      preload_idx = load_order.index { |p| p.include?("rails_helper") }
      expect(rspec_idx).not_to be_nil, "expected require 'rspec/core' to be called"
      expect(preload_idx).not_to be_nil, "expected preload file to be required"
      expect(rspec_idx).to be < preload_idx
    end
  end
end
