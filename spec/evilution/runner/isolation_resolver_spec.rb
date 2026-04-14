# frozen_string_literal: true

require "tmpdir"
require "evilution/config"
require "evilution/runner/isolation_resolver"

RSpec.describe Evilution::Runner::IsolationResolver do
  def config(**overrides)
    Evilution::Config.new(quiet: true, baseline: false, skip_config_file: true, **overrides)
  end

  def target_files_callback(files)
    -> { files }
  end

  describe "#isolator" do
    it "returns a Fork isolator when config.isolation is :fork" do
      resolver = described_class.new(config(isolation: :fork), target_files: -> { [] }, hooks: nil)
      expect(resolver.isolator).to be_a(Evilution::Isolation::Fork)
    end

    it "returns an InProcess isolator when config.isolation is :in_process" do
      resolver = described_class.new(config(isolation: :in_process), target_files: -> { [] }, hooks: nil)
      expect(resolver.isolator).to be_a(Evilution::Isolation::InProcess)
    end

    it "auto-selects InProcess when no Rails root is detected" do
      resolver = described_class.new(config(isolation: :auto), target_files: -> { [] }, hooks: nil)
      allow(Evilution::RailsDetector).to receive(:rails_root_for_any).and_return(nil)
      expect(resolver.isolator).to be_a(Evilution::Isolation::InProcess)
    end

    it "auto-selects Fork when a Rails root is detected" do
      resolver = described_class.new(config(isolation: :auto), target_files: -> { [] }, hooks: nil)
      allow(Evilution::RailsDetector).to receive(:rails_root_for_any).and_return("/app")
      expect(resolver.isolator).to be_a(Evilution::Isolation::Fork)
    end

    it "memoizes the isolator instance" do
      resolver = described_class.new(config(isolation: :fork), target_files: -> { [] }, hooks: nil)
      expect(resolver.isolator).to equal(resolver.isolator)
    end
  end

  describe "#rails_root_detected?" do
    it "delegates to RailsDetector with the target files callback" do
      files = ["lib/foo.rb"]
      allow(Evilution::RailsDetector).to receive(:rails_root_for_any).with(files).and_return("/app")
      resolver = described_class.new(config, target_files: -> { files }, hooks: nil)

      expect(resolver.rails_root_detected?).to be(true)
    end

    it "memoizes the detection result" do
      resolver = described_class.new(config, target_files: -> { [] }, hooks: nil)
      allow(Evilution::RailsDetector).to receive(:rails_root_for_any).and_return(nil)

      resolver.rails_root_detected?
      resolver.rails_root_detected?
      expect(Evilution::RailsDetector).to have_received(:rails_root_for_any).once
    end
  end

  describe "warning when in_process is requested on Rails" do
    it "warns once when config.isolation is :in_process and a Rails root is detected" do
      allow(Evilution::RailsDetector).to receive(:rails_root_for_any).and_return("/app")
      noisy_config = Evilution::Config.new(isolation: :in_process, baseline: false, skip_config_file: true)
      resolver = described_class.new(noisy_config, target_files: -> { [] }, hooks: nil)

      expect { resolver.isolator }.to output(/unsafe on Rails/).to_stderr
      expect { resolver.isolator }.not_to output.to_stderr
    end

    it "suppresses the warning when config.quiet is set" do
      allow(Evilution::RailsDetector).to receive(:rails_root_for_any).and_return("/app")
      resolver = described_class.new(
        config(isolation: :in_process, quiet: true), target_files: -> { [] }, hooks: nil
      )
      expect { resolver.isolator }.not_to output.to_stderr
    end
  end

  describe "#perform_preload" do
    it "is a no-op when config.preload is false" do
      resolver = described_class.new(
        config(preload: false, isolation: :fork), target_files: -> { [] }, hooks: nil
      )
      expect { resolver.perform_preload }.not_to raise_error
    end

    it "is a no-op when isolation resolves to :in_process" do
      resolver = described_class.new(
        config(isolation: :in_process), target_files: -> { [] }, hooks: nil
      )
      expect { resolver.perform_preload }.not_to raise_error
    end

    it "raises Evilution::ConfigError when an explicit preload path is missing" do
      resolver = described_class.new(
        config(preload: "/nonexistent/helper.rb", isolation: :fork),
        target_files: -> { [] }, hooks: nil
      )
      expect { resolver.perform_preload }.to raise_error(Evilution::ConfigError, /preload file not found/)
    end

    it "loads a preload file when one is provided" do
      Dir.mktmpdir do |dir|
        preload_file = File.join(dir, "preloaded.rb")
        marker = File.join(dir, "marker")
        File.write(preload_file, "File.write(#{marker.inspect}, 'loaded')\n")

        resolver = described_class.new(
          config(preload: preload_file, isolation: :fork),
          target_files: -> { [] }, hooks: nil
        )
        resolver.perform_preload

        expect(File.read(marker)).to eq("loaded")
      end
    end
  end
end
