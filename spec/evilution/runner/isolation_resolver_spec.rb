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

    it "forwards the hooks object to the Fork isolator" do
      hooks = Object.new
      resolver = described_class.new(config(isolation: :fork), target_files: -> { [] }, hooks: hooks)
      expect(Evilution::Isolation::Fork).to receive(:new).with(hooks: hooks).and_call_original
      resolver.isolator
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

    it "returns the same cached boolean on every call" do
      allow(Evilution::RailsDetector).to receive(:rails_root_for_any).and_return("/app")
      resolver = described_class.new(config, target_files: -> { [] }, hooks: nil)

      first = resolver.rails_root_detected?
      expect(first).to be(true)
      expect(resolver.rails_root_detected?).to be(true)
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

    it "warns at most once even across separate isolation resolutions" do
      allow(Evilution::RailsDetector).to receive(:rails_root_for_any).and_return("/app")
      noisy_config = Evilution::Config.new(isolation: :in_process, baseline: false, skip_config_file: true)
      resolver = described_class.new(noisy_config, target_files: -> { [] }, hooks: nil)

      written = +""
      allow($stderr).to receive(:write) { |str| written << str }

      resolver.isolator
      resolver.perform_preload

      expect(written.scan("unsafe on Rails").size).to eq(1)
    end
  end

  describe "#perform_preload" do
    it "is a no-op when config.preload is false" do
      resolver = described_class.new(
        config(preload: false, isolation: :fork), target_files: -> { [] }, hooks: nil
      )
      expect { resolver.perform_preload }.not_to raise_error
    end

    it "does not auto-detect a preload file when config.preload is false even under :fork on Rails" do
      Dir.mktmpdir do |dir|
        spec_dir = File.join(dir, "spec")
        FileUtils.mkdir_p(spec_dir)
        marker = File.join(dir, "marker")
        File.write(File.join(spec_dir, "rails_helper.rb"), "File.write(#{marker.inspect}, 'loaded')\n")
        allow(Evilution::RailsDetector).to receive(:rails_root_for_any).and_return(dir)

        resolver = described_class.new(
          config(preload: false, isolation: :fork), target_files: -> { [] }, hooks: nil
        )
        resolver.perform_preload

        expect(File.exist?(marker)).to be(false)
      end
    end

    it "is a no-op when isolation resolves to :in_process" do
      resolver = described_class.new(
        config(isolation: :in_process), target_files: -> { [] }, hooks: nil
      )
      expect { resolver.perform_preload }.not_to raise_error
    end

    it "detects the Rails root only once while resolving a preload" do
      Dir.mktmpdir do |dir|
        spec_dir = File.join(dir, "spec")
        FileUtils.mkdir_p(spec_dir)
        File.write(File.join(spec_dir, "rails_helper.rb"), "# preloaded\n")
        allow(Evilution::RailsDetector).to receive(:rails_root_for_any).and_return(dir)
        original_load_path = $LOAD_PATH.dup

        begin
          resolver = described_class.new(config(isolation: :fork), target_files: -> { [] }, hooks: nil)
          resolver.perform_preload
        ensure
          $LOAD_PATH.replace(original_load_path)
        end

        expect(Evilution::RailsDetector).to have_received(:rails_root_for_any).once
      end
    end

    it "adds the rails root spec directory to $LOAD_PATH before requiring the preload file" do
      Dir.mktmpdir do |dir|
        spec_dir = File.join(dir, "spec")
        FileUtils.mkdir_p(spec_dir)
        File.write(File.join(spec_dir, "rails_helper.rb"), "# preloaded\n")
        allow(Evilution::RailsDetector).to receive(:rails_root_for_any).and_return(dir)
        expanded = File.expand_path(spec_dir)
        original_load_path = $LOAD_PATH.dup

        begin
          resolver = described_class.new(config(isolation: :fork), target_files: -> { [] }, hooks: nil)
          resolver.perform_preload
          expect($LOAD_PATH).to include(expanded)
        ensure
          $LOAD_PATH.replace(original_load_path)
        end
      end
    end

    it "raises Evilution::ConfigError when an explicit preload path is missing under :fork with no rails root" do
      resolver = described_class.new(
        config(preload: "/nonexistent/helper.rb", isolation: :fork),
        target_files: -> { [] }, hooks: nil
      )
      expect { resolver.perform_preload }.to raise_error(Evilution::ConfigError, /[Pp]reload file not found/)
    end

    it "wraps a failing preload file in a ConfigError naming the quoted path, error class and message" do
      Dir.mktmpdir do |dir|
        preload_file = File.join(dir, "preloaded.rb")
        File.write(preload_file, "raise 'boom-from-preload'\n")

        resolver = described_class.new(
          config(preload: preload_file, isolation: :fork),
          target_files: -> { [] }, hooks: nil
        )

        expect { resolver.perform_preload }.to raise_error(Evilution::ConfigError) do |e|
          expect(e.message).to include("failed to preload #{preload_file.inspect}")
          expect(e.message).to include("RuntimeError")
          expect(e.message).to include("boom-from-preload")
        end
      end
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

    it "stubs Minitest.autorun before requiring the user preload file when integration is :minitest" do
      Dir.mktmpdir do |dir|
        preload_file = File.join(dir, "preloaded.rb")
        marker = File.join(dir, "marker")
        File.write(preload_file, <<~PRE)
          require "minitest"
          loc = ::Minitest.singleton_class.instance_method(:autorun).source_location
          File.write(#{marker.inspect}, loc ? loc.first : "nil")
        PRE

        resolver = described_class.new(
          config(preload: preload_file, isolation: :fork, integration: :minitest),
          target_files: -> { [] }, hooks: nil
        )
        resolver.perform_preload

        expect(File.read(marker)).to end_with("lib/evilution/integration/minitest.rb")
      end
    end

    it "does not stub Minitest.autorun when integration is :rspec" do
      Dir.mktmpdir do |dir|
        preload_file = File.join(dir, "preloaded.rb")
        File.write(preload_file, "# noop\n")

        resolver = described_class.new(
          config(preload: preload_file, isolation: :fork, integration: :rspec),
          target_files: -> { [] }, hooks: nil
        )

        expect(Evilution::Integration::Minitest).not_to receive(:stub_autorun!)

        resolver.perform_preload
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

    it "does not fall through to auto-detect under :in_process even when a Rails root with helpers exists" do
      Dir.mktmpdir do |dir|
        spec_dir = File.join(dir, "spec")
        FileUtils.mkdir_p(spec_dir)
        marker = File.join(dir, "marker")
        File.write(File.join(spec_dir, "rails_helper.rb"), "File.write(#{marker.inspect}, 'loaded')\n")
        allow(Evilution::RailsDetector).to receive(:rails_root_for_any).and_return(dir)

        resolver = described_class.new(
          config(preload: "/nonexistent/helper.rb", isolation: :in_process),
          target_files: -> { [] }, hooks: nil
        )

        expect { resolver.perform_preload }.to raise_error(
          Evilution::ConfigError, %r{preload file not found: "/nonexistent/helper\.rb"}
        )
        expect(File.exist?(marker)).to be(false)
      end
    end

    describe "autodetect fallback chain (Rails detected, no explicit preload)" do
      def with_rails_root_having(file_paths)
        Dir.mktmpdir do |dir|
          markers = file_paths.to_h { |rel| [rel, write_marker_file(dir, rel)] }
          allow(Evilution::RailsDetector).to receive(:rails_root_for_any).and_return(dir)
          yield(dir, markers)
        end
      end

      def write_marker_file(dir, rel)
        abs = File.join(dir, rel)
        FileUtils.mkdir_p(File.dirname(abs))
        marker = File.join(dir, "marker_#{File.basename(rel, ".rb")}")
        File.write(abs, "File.write(#{marker.inspect}, #{rel.inspect})\n")
        marker
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

      it "joins the tried candidate paths with a comma and no surrounding quotes" do
        Dir.mktmpdir do |dir|
          allow(Evilution::RailsDetector).to receive(:rails_root_for_any).and_return(dir)
          resolver = described_class.new(config(isolation: :fork), target_files: -> { [] }, hooks: nil)

          expect { resolver.perform_preload }.to raise_error(Evilution::ConfigError) do |e|
            expect(e.message).to include(
              "spec/rails_helper.rb, spec/spec_helper.rb, test/test_helper.rb"
            )
          end
        end
      end

      it "is a no-op under :in_process even when Rails is detected and no helpers exist" do
        Dir.mktmpdir do |dir|
          allow(Evilution::RailsDetector).to receive(:rails_root_for_any).and_return(dir)
          resolver = described_class.new(
            config(isolation: :in_process), target_files: -> { [] }, hooks: nil
          )
          expect { resolver.perform_preload }.not_to raise_error
        end
      end
    end

    describe "missing explicit preload with autodetect fallback under :fork" do
      it "warns to stderr and loads the autodetected fallback when one exists" do
        Dir.mktmpdir do |dir|
          spec_dir = File.join(dir, "spec")
          FileUtils.mkdir_p(spec_dir)
          rails_helper = File.join(spec_dir, "rails_helper.rb")
          marker = File.join(dir, "marker")
          File.write(rails_helper, "File.write(#{marker.inspect}, 'fallback')\n")

          allow(Evilution::RailsDetector).to receive(:rails_root_for_any).and_return(dir)
          noisy_config = Evilution::Config.new(
            preload: "/nonexistent/helper.rb",
            isolation: :fork,
            baseline: false,
            skip_config_file: true
          )
          resolver = described_class.new(noisy_config, target_files: -> { [] }, hooks: nil)

          expect { resolver.perform_preload }.to output(
            %r{configured preload "/nonexistent/helper\.rb" not found; falling through to auto-detect chain}
          ).to_stderr
          expect(File.read(marker)).to eq("fallback")
        end
      end

      it "raises a combined error naming both the missing explicit path and every chain entry" do
        Dir.mktmpdir do |dir|
          allow(Evilution::RailsDetector).to receive(:rails_root_for_any).and_return(dir)
          resolver = described_class.new(
            config(preload: "/nonexistent/helper.rb", isolation: :fork),
            target_files: -> { [] }, hooks: nil
          )

          expect { resolver.perform_preload }.to raise_error(Evilution::ConfigError) do |e|
            expect(e.message).to include("/nonexistent/helper.rb")
            expect(e.message).to include("spec/rails_helper.rb")
            expect(e.message).to include("spec/spec_helper.rb")
            expect(e.message).to include("test/test_helper.rb")
          end
        end
      end

      it "quotes the configured explicit path and comma-joins the chain in the combined error" do
        Dir.mktmpdir do |dir|
          allow(Evilution::RailsDetector).to receive(:rails_root_for_any).and_return(dir)
          resolver = described_class.new(
            config(preload: "/nonexistent/helper.rb", isolation: :fork),
            target_files: -> { [] }, hooks: nil
          )

          expect { resolver.perform_preload }.to raise_error(Evilution::ConfigError) do |e|
            expect(e.message).to include('Configured preload "/nonexistent/helper.rb" does not exist')
            expect(e.message).to include(
              "spec/rails_helper.rb, spec/spec_helper.rb, test/test_helper.rb"
            )
          end
        end
      end

      it "suppresses the missing-preload warning when config.quiet is true" do
        Dir.mktmpdir do |dir|
          spec_dir = File.join(dir, "spec")
          FileUtils.mkdir_p(spec_dir)
          File.write(File.join(spec_dir, "rails_helper.rb"), "# preloaded\n")
          allow(Evilution::RailsDetector).to receive(:rails_root_for_any).and_return(dir)
          resolver = described_class.new(
            config(preload: "/nonexistent/helper.rb", isolation: :fork),
            target_files: -> { [] }, hooks: nil
          )

          expect { resolver.perform_preload }.not_to output.to_stderr
        end
      end
    end

    describe "autodetect fallback for Ruby gems (non-Rails)" do
      it "preloads lib/<name>.rb when target lives under a gem with a gemspec and no Rails root" do
        Dir.mktmpdir do |dir|
          File.write(File.join(dir, "mygem.gemspec"), "# spec\n")
          lib_dir = File.join(dir, "lib")
          FileUtils.mkdir_p(lib_dir)
          marker = File.join(dir, "marker")
          File.write(File.join(lib_dir, "mygem.rb"), "File.write(#{marker.inspect}, 'gem-entry')\n")
          allow(Evilution::RailsDetector).to receive(:rails_root_for_any).and_return(nil)
          Evilution::GemDetector.reset_cache!

          resolver = described_class.new(
            config(isolation: :fork),
            target_files: -> { [File.join(lib_dir, "mygem.rb")] },
            hooks: nil
          )
          resolver.perform_preload

          expect(File.read(marker)).to eq("gem-entry")
        end
      end

      it "prefers Rails rails_helper over gem entry when both signals are present" do
        Dir.mktmpdir do |dir|
          File.write(File.join(dir, "mygem.gemspec"), "# spec\n")
          lib_dir = File.join(dir, "lib")
          spec_dir = File.join(dir, "spec")
          FileUtils.mkdir_p(lib_dir)
          FileUtils.mkdir_p(spec_dir)
          rails_marker = File.join(dir, "marker_rails")
          gem_marker = File.join(dir, "marker_gem")
          File.write(File.join(spec_dir, "rails_helper.rb"), "File.write(#{rails_marker.inspect}, 'rails')\n")
          File.write(File.join(lib_dir, "mygem.rb"), "File.write(#{gem_marker.inspect}, 'gem')\n")
          allow(Evilution::RailsDetector).to receive(:rails_root_for_any).and_return(dir)
          Evilution::GemDetector.reset_cache!

          resolver = described_class.new(
            config(isolation: :fork), target_files: -> { [] }, hooks: nil
          )
          resolver.perform_preload

          expect(File.read(rails_marker)).to eq("rails")
          expect(File.exist?(gem_marker)).to be(false)
        end
      end

      it "is a no-op under :in_process even when gem entry is autodetected" do
        Dir.mktmpdir do |dir|
          File.write(File.join(dir, "mygem.gemspec"), "# spec\n")
          lib_dir = File.join(dir, "lib")
          FileUtils.mkdir_p(lib_dir)
          marker = File.join(dir, "marker")
          File.write(File.join(lib_dir, "mygem.rb"), "File.write(#{marker.inspect}, 'gem-entry')\n")
          allow(Evilution::RailsDetector).to receive(:rails_root_for_any).and_return(nil)
          Evilution::GemDetector.reset_cache!

          resolver = described_class.new(
            config(isolation: :in_process),
            target_files: -> { [File.join(lib_dir, "mygem.rb")] },
            hooks: nil
          )
          resolver.perform_preload

          expect(File.exist?(marker)).to be(false)
        end
      end

      it "memoizes the detected gem entry across repeated lookups" do
        Dir.mktmpdir do |dir|
          File.write(File.join(dir, "mygem.gemspec"), "# spec\n")
          lib_dir = File.join(dir, "lib")
          FileUtils.mkdir_p(lib_dir)
          File.write(File.join(lib_dir, "mygem.rb"), "# entry\n")
          allow(Evilution::RailsDetector).to receive(:rails_root_for_any).and_return(nil)
          Evilution::GemDetector.reset_cache!
          allow(Evilution::GemDetector).to receive(:gem_root_for_any).and_call_original

          resolver = described_class.new(
            config(isolation: :fork),
            target_files: -> { [File.join(lib_dir, "mygem.rb")] },
            hooks: nil
          )

          first = resolver.send(:detected_gem_entry)
          second = resolver.send(:detected_gem_entry)

          expect(second).to eq(first)
          expect(first).to end_with("lib/mygem.rb")
          expect(Evilution::GemDetector).to have_received(:gem_root_for_any).once
        end
      end

      it "is a silent no-op when neither Rails nor gem is detected under :fork" do
        Dir.mktmpdir do |dir|
          allow(Evilution::RailsDetector).to receive(:rails_root_for_any).and_return(nil)
          Evilution::GemDetector.reset_cache!
          resolver = described_class.new(
            config(isolation: :fork),
            target_files: -> { [File.join(dir, "thing.rb")] },
            hooks: nil
          )

          expect { resolver.perform_preload }.not_to raise_error
        end
      end
    end
  end
end
