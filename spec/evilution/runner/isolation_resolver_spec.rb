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

    it "loads an explicit preload file under :in_process isolation" do
      Dir.mktmpdir do |dir|
        preload_file = File.join(dir, "preloaded.rb")
        marker = File.join(dir, "marker")
        File.write(preload_file, "File.write(#{marker.inspect}, 'loaded')\n")

        resolver = described_class.new(
          config(preload: preload_file, isolation: :in_process),
          target_files: -> { [] }, hooks: nil
        )
        resolver.perform_preload

        expect(File.read(marker)).to eq("loaded")
      end
    end

    it "loads an explicit preload file under :auto when no Rails root is detected" do
      allow(Evilution::RailsDetector).to receive(:rails_root_for_any).and_return(nil)
      Dir.mktmpdir do |dir|
        preload_file = File.join(dir, "preloaded.rb")
        marker = File.join(dir, "marker")
        File.write(preload_file, "File.write(#{marker.inspect}, 'loaded')\n")

        resolver = described_class.new(
          config(preload: preload_file, isolation: :auto),
          target_files: -> { [] }, hooks: nil
        )
        resolver.perform_preload

        expect(File.read(marker)).to eq("loaded")
      end
    end

    it "skips auto-detected rails_helper under explicit :in_process isolation" do
      Dir.mktmpdir do |dir|
        spec_dir = File.join(dir, "spec")
        FileUtils.mkdir_p(spec_dir)
        rails_helper = File.join(spec_dir, "rails_helper.rb")
        marker = File.join(dir, "marker")
        File.write(rails_helper, "File.write(#{marker.inspect}, 'loaded')\n")

        allow(Evilution::RailsDetector).to receive(:rails_root_for_any).and_return(dir)
        resolver = described_class.new(
          config(isolation: :in_process), target_files: -> { [] }, hooks: nil
        )
        resolver.perform_preload

        expect(File.exist?(marker)).to be(false)
      end
    end

    it "raises Evilution::ConfigError when explicit preload is missing under :in_process" do
      resolver = described_class.new(
        config(preload: "/nonexistent/helper.rb", isolation: :in_process),
        target_files: -> { [] }, hooks: nil
      )
      expect { resolver.perform_preload }.to raise_error(Evilution::ConfigError, /preload file not found/)
    end

    describe "autodetect fallback chain (Rails detected, no explicit preload)" do
      def with_rails_root_having(file_paths)
        Dir.mktmpdir do |dir|
          markers = {}
          file_paths.each do |rel|
            abs = File.join(dir, rel)
            FileUtils.mkdir_p(File.dirname(abs))
            marker = File.join(dir, "marker_#{File.basename(rel, ".rb")}")
            markers[rel] = marker
            File.write(abs, "File.write(#{marker.inspect}, #{rel.inspect})\n")
          end
          allow(Evilution::RailsDetector).to receive(:rails_root_for_any).and_return(dir)
          yield(dir, markers)
        end
      end

      it "loads spec/rails_helper.rb when present" do
        with_rails_root_having(["spec/rails_helper.rb", "spec/spec_helper.rb"]) do |_dir, markers|
          resolver = described_class.new(config(isolation: :fork), target_files: -> { [] }, hooks: nil)
          resolver.perform_preload
          expect(File.read(markers["spec/rails_helper.rb"])).to eq("spec/rails_helper.rb")
          expect(File.exist?(markers["spec/spec_helper.rb"])).to be(false)
        end
      end

      it "falls back to spec/spec_helper.rb when rails_helper is absent" do
        with_rails_root_having(["spec/spec_helper.rb"]) do |_dir, markers|
          resolver = described_class.new(config(isolation: :fork), target_files: -> { [] }, hooks: nil)
          resolver.perform_preload
          expect(File.read(markers["spec/spec_helper.rb"])).to eq("spec/spec_helper.rb")
        end
      end

      it "falls back to test/test_helper.rb when no spec helpers exist" do
        with_rails_root_having(["test/test_helper.rb"]) do |_dir, markers|
          resolver = described_class.new(config(isolation: :fork), target_files: -> { [] }, hooks: nil)
          resolver.perform_preload
          expect(File.read(markers["test/test_helper.rb"])).to eq("test/test_helper.rb")
        end
      end

      it "raises ConfigError listing every tried path when chain finds nothing" do
        Dir.mktmpdir do |dir|
          allow(Evilution::RailsDetector).to receive(:rails_root_for_any).and_return(dir)
          resolver = described_class.new(config(isolation: :fork), target_files: -> { [] }, hooks: nil)

          expect { resolver.perform_preload }.to raise_error(Evilution::ConfigError) do |e|
            expect(e.message).to include("spec/rails_helper.rb")
            expect(e.message).to include("spec/spec_helper.rb")
            expect(e.message).to include("test/test_helper.rb")
            expect(e.message).to match(/--preload|preload:/)
          end
        end
      end
    end
  end
end
