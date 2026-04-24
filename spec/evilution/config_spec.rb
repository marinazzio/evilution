# frozen_string_literal: true

require "tempfile"
require "tmpdir"
require "fileutils"

RSpec.describe Evilution::Config do
  describe "constants" do
    it "exposes CONFIG_FILES with the expected search order" do
      expect(described_class::CONFIG_FILES).to eq(%w[.evilution.yml config/evilution.yml])
    end

    it "freezes CONFIG_FILES" do
      expect(described_class::CONFIG_FILES).to be_frozen
    end

    it "exposes DEFAULTS with representative defaults" do
      expect(described_class::DEFAULTS).to include(
        timeout: 30, format: :text, integration: :rspec, jobs: 1, isolation: :auto
      )
    end

    it "freezes DEFAULTS" do
      expect(described_class::DEFAULTS).to be_frozen
    end
  end

  describe "defaults" do
    subject(:config) { described_class.new(skip_config_file: true) }

    it "sets target_files to empty array" do
      expect(config.target_files).to eq([])
    end

    it "sets timeout to 30 seconds" do
      expect(config.timeout).to eq(30)
    end

    it "sets format to :text" do
      expect(config.format).to eq(:text)
    end

    it "sets min_score to 0.0" do
      expect(config.min_score).to eq(0.0)
    end

    it "sets integration to :rspec (Symbol)" do
      expect(config.integration).to eq(:rspec)
      expect(config.integration).to be_a(Symbol)
    end

    it "disables verbose by default" do
      expect(config.verbose).to be false
    end

    it "disables quiet by default" do
      expect(config.quiet).to be false
    end

    it "sets fail_fast to nil" do
      expect(config.fail_fast).to be_nil
    end

    it "sets line_ranges to empty hash" do
      expect(config.line_ranges).to eq({})
    end

    it "sets spec_files to empty array" do
      expect(config.spec_files).to eq([])
    end

    it "disables suggest_tests by default" do
      expect(config.suggest_tests).to be false
    end

    it "sets ignore_patterns to an empty Array" do
      expect(config.ignore_patterns).to eq([])
      expect(config.ignore_patterns).to be_a(Array)
    end

    it "defaults hooks to empty hash" do
      expect(config.hooks).to eq({})
    end

    it "defaults jobs to 1" do
      expect(config.jobs).to eq(1)
    end

    it "defaults isolation to :auto" do
      expect(config.isolation).to eq(:auto)
    end
  end

  describe "custom options" do
    it "accepts target_files as array" do
      config = described_class.new(target_files: ["lib/foo.rb", "lib/bar.rb"], skip_config_file: true)

      expect(config.target_files).to eq(["lib/foo.rb", "lib/bar.rb"])
    end

    it "wraps single target_file in array" do
      config = described_class.new(target_files: "lib/foo.rb", skip_config_file: true)

      expect(config.target_files).to eq(["lib/foo.rb"])
    end

    it "accepts custom jobs" do
      config = described_class.new(jobs: 4, skip_config_file: true)

      expect(config.jobs).to eq(4)
    end

    it "accepts custom timeout" do
      config = described_class.new(timeout: 30, skip_config_file: true)

      expect(config.timeout).to eq(30)
    end

    it "accepts format as string" do
      config = described_class.new(format: "json", skip_config_file: true)

      expect(config.format).to eq(:json)
    end

    it "accepts min_score" do
      config = described_class.new(min_score: 0.9, skip_config_file: true)

      expect(config.min_score).to eq(0.9)
    end

    it "accepts spec_files" do
      config = described_class.new(spec_files: ["spec/foo_spec.rb"], skip_config_file: true)

      expect(config.spec_files).to eq(["spec/foo_spec.rb"])
    end

    it "wraps single spec_file in array" do
      config = described_class.new(spec_files: "spec/foo_spec.rb", skip_config_file: true)

      expect(config.spec_files).to eq(["spec/foo_spec.rb"])
    end

    it "accepts hooks configuration" do
      hooks_config = { worker_process_start: "config/hooks/worker.rb" }
      config = described_class.new(hooks: hooks_config, skip_config_file: true)

      expect(config.hooks).to eq(hooks_config)
    end

    it "accepts fail_fast" do
      config = described_class.new(fail_fast: 3, skip_config_file: true)

      expect(config.fail_fast).to eq(3)
    end

    it "accepts suggest_tests" do
      config = described_class.new(suggest_tests: true, skip_config_file: true)

      expect(config.suggest_tests).to be true
    end
  end

  describe "config file loading (orchestration)" do
    around do |example|
      Dir.mktmpdir do |dir|
        Dir.chdir(dir) { example.run }
      end
    end

    it "loads settings from .evilution.yml" do
      File.write(".evilution.yml", "timeout: 30\nformat: json\n")

      config = described_class.new

      expect(config.timeout).to eq(30)
      expect(config.format).to eq(:json)
    end

    it "CLI options override file settings" do
      File.write(".evilution.yml", "timeout: 30\n")

      config = described_class.new(timeout: 5)

      expect(config.timeout).to eq(5)
    end

    it "skip_config_file: true bypasses file reading" do
      File.write(".evilution.yml", "timeout: 999\n")

      config = described_class.new(skip_config_file: true)

      expect(config.timeout).to eq(30)
    end

    it "end-to-end merge exposes both file and explicit values" do
      File.write(".evilution.yml", "timeout: 60\nformat: json\n")

      config = described_class.new(jobs: 4)

      expect(config.timeout).to eq(60)
      expect(config.format).to eq(:json)
      expect(config.jobs).to eq(4)
    end
  end

  describe ".file_options" do
    around do |example|
      Dir.mktmpdir do |dir|
        Dir.chdir(dir) { example.run }
      end
    end

    it "delegates to FileLoader and returns parsed symbol-keyed options" do
      File.write(".evilution.yml", "timeout: 42\n")

      expect(described_class.file_options).to eq(timeout: 42)
    end

    it "returns {} when no config file exists" do
      expect(described_class.file_options).to eq({})
    end
  end

  describe "#spec_selector" do
    it "returns an Evilution::SpecSelector instance" do
      config = described_class.new(skip_config_file: true)

      expect(config.spec_selector).to be_a(Evilution::SpecSelector)
    end

    it "returns the same memoized instance on repeated calls" do
      config = described_class.new(skip_config_file: true)

      expect(config.spec_selector).to be(config.spec_selector)
    end

    it "uses configured spec_files" do
      config = described_class.new(skip_config_file: true, spec_files: ["spec/explicit_spec.rb"])

      expect(config.spec_selector.call("app/anything.rb")).to eq(["spec/explicit_spec.rb"])
    end

    it "uses configured spec_mappings" do
      Dir.mktmpdir do |dir|
        Dir.chdir(dir) do
          FileUtils.mkdir_p("spec/requests")
          File.write("spec/requests/games_overlay_spec.rb", "")
          config = described_class.new(
            skip_config_file: true,
            spec_mappings: { "app/controllers/games_controller.rb" => ["spec/requests/games_overlay_spec.rb"] }
          )

          expect(config.spec_selector.call("app/controllers/games_controller.rb"))
            .to eq(["spec/requests/games_overlay_spec.rb"])
        end
      end
    end

    it "uses configured spec_pattern" do
      Dir.mktmpdir do |dir|
        Dir.chdir(dir) do
          FileUtils.mkdir_p("spec/controllers")
          FileUtils.mkdir_p("spec/requests")
          File.write("spec/controllers/foo_controller_spec.rb", "")
          File.write("spec/requests/foo_spec.rb", "")
          config = described_class.new(
            skip_config_file: true,
            spec_pattern: "spec/controllers/**/*_spec.rb"
          )

          expect(config.spec_selector.call("app/controllers/foo_controller.rb"))
            .to eq(["spec/controllers/foo_controller_spec.rb"])
        end
      end
    end

    it "resolves test/ paths when integration is :minitest" do
      Dir.mktmpdir do |dir|
        Dir.chdir(dir) do
          FileUtils.mkdir_p("test/foo")
          File.write("test/foo/bar_test.rb", "")
          config = described_class.new(skip_config_file: true, integration: :minitest)

          expect(config.spec_selector.call("lib/foo/bar.rb")).to eq(["test/foo/bar_test.rb"])
        end
      end
    end

    it "resolves spec/ paths when integration is :rspec" do
      Dir.mktmpdir do |dir|
        Dir.chdir(dir) do
          FileUtils.mkdir_p("spec/foo")
          File.write("spec/foo/bar_spec.rb", "")
          config = described_class.new(skip_config_file: true, integration: :rspec)

          expect(config.spec_selector.call("lib/foo/bar.rb")).to eq(["spec/foo/bar_spec.rb"])
        end
      end
    end
  end

  describe ".default_template" do
    it "returns a non-empty YAML string containing the Evilution configuration header" do
      template = described_class.default_template

      expect(template).not_to be_empty
      expect(template).to include("Evilution configuration")
    end

    it "includes commented-out options" do
      template = described_class.default_template

      expect(template).to include("# timeout:")
      expect(template).to include("# format:")
    end
  end

  describe "predicate methods" do
    describe "#json?" do
      it "returns true when format is json" do
        config = described_class.new(format: :json, skip_config_file: true)

        expect(config.json?).to be true
      end

      it "returns false when format is text" do
        config = described_class.new(format: :text, skip_config_file: true)

        expect(config.json?).to be false
      end
    end

    describe "#text?" do
      it "returns true when format is text" do
        config = described_class.new(format: :text, skip_config_file: true)

        expect(config.text?).to be true
      end

      it "returns false when format is json" do
        config = described_class.new(format: :json, skip_config_file: true)

        expect(config.text?).to be false
      end
    end

    describe "#html?" do
      it "returns true when format is html" do
        config = described_class.new(format: :html, skip_config_file: true)

        expect(config.html?).to be true
      end

      it "returns false when format is text" do
        config = described_class.new(format: :text, skip_config_file: true)

        expect(config.html?).to be false
      end
    end

    describe "#line_ranges?" do
      it "returns true when line_ranges is non-empty" do
        config = described_class.new(line_ranges: { "lib/foo.rb" => 10..20 }, skip_config_file: true)

        expect(config.line_ranges?).to be true
      end

      it "returns false when line_ranges is empty" do
        config = described_class.new(skip_config_file: true)

        expect(config.line_ranges?).to be false
      end
    end

    describe "#target?" do
      it "returns true when target is set" do
        config = described_class.new(target: "Foo#bar", skip_config_file: true)

        expect(config.target?).to be true
      end

      it "returns false when target is nil" do
        config = described_class.new(skip_config_file: true)

        expect(config.target?).to be false
      end
    end

    describe "#fail_fast?" do
      it "returns true when fail_fast is set" do
        config = described_class.new(fail_fast: 1, skip_config_file: true)

        expect(config.fail_fast?).to be true
      end

      it "returns false when fail_fast is nil" do
        config = described_class.new(skip_config_file: true)

        expect(config.fail_fast?).to be false
      end
    end

    describe "#suggest_tests?" do
      it "returns true when suggest_tests is enabled" do
        config = described_class.new(suggest_tests: true, skip_config_file: true)

        expect(config.suggest_tests?).to be true
      end

      it "returns false when suggest_tests is disabled" do
        config = described_class.new(skip_config_file: true)

        expect(config.suggest_tests?).to be false
      end
    end

    describe "#progress?" do
      it "returns true by default" do
        config = described_class.new(skip_config_file: true)

        expect(config.progress?).to be true
      end

      it "returns false when progress is disabled" do
        config = described_class.new(progress: false, skip_config_file: true)

        expect(config.progress?).to be false
      end
    end

    describe "#show_disabled?" do
      it "returns false by default" do
        config = described_class.new(skip_config_file: true)

        expect(config.show_disabled?).to be false
      end

      it "returns true when show_disabled is enabled" do
        config = described_class.new(show_disabled: true, skip_config_file: true)

        expect(config.show_disabled?).to be true
      end
    end

    describe "#skip_heredoc_literals?" do
      it "returns false by default" do
        config = described_class.new(skip_config_file: true)

        expect(config.skip_heredoc_literals?).to be false
      end

      it "returns true when skip_heredoc_literals is enabled" do
        config = described_class.new(skip_heredoc_literals: true, skip_config_file: true)

        expect(config.skip_heredoc_literals?).to be true
      end
    end

    describe "#related_specs_heuristic?" do
      it "returns false by default" do
        config = described_class.new(skip_config_file: true)

        expect(config.related_specs_heuristic?).to be false
      end

      it "returns true when related_specs_heuristic is enabled" do
        config = described_class.new(related_specs_heuristic: true, skip_config_file: true)

        expect(config.related_specs_heuristic?).to be true
      end
    end

    describe "#fallback_to_full_suite?" do
      it "returns false by default" do
        config = described_class.new(skip_config_file: true)

        expect(config.fallback_to_full_suite?).to be false
      end

      it "returns true when enabled" do
        config = described_class.new(fallback_to_full_suite: true, skip_config_file: true)

        expect(config.fallback_to_full_suite?).to be true
      end
    end
  end

  describe "example_targeting (orchestration)" do
    around do |example|
      original = ENV.fetch("EV_DISABLE_EXAMPLE_TARGETING", :__unset__)
      ENV.delete("EV_DISABLE_EXAMPLE_TARGETING")
      example.run
    ensure
      if original == :__unset__
        ENV.delete("EV_DISABLE_EXAMPLE_TARGETING")
      else
        ENV["EV_DISABLE_EXAMPLE_TARGETING"] = original
      end
    end

    it "defaults to true" do
      config = described_class.new(skip_config_file: true)

      expect(config.example_targeting?).to be true
    end

    it "accepts false explicitly" do
      config = described_class.new(example_targeting: false, skip_config_file: true)

      expect(config.example_targeting?).to be false
    end

    it "loads example_targeting from YAML" do
      Dir.mktmpdir do |dir|
        Dir.chdir(dir) do
          File.write(".evilution.yml", "example_targeting: false\n")

          expect(described_class.new.example_targeting?).to be false
        end
      end
    end

    it "CLI options override example_targeting from file" do
      Dir.mktmpdir do |dir|
        Dir.chdir(dir) do
          File.write(".evilution.yml", "example_targeting: false\n")

          expect(described_class.new(example_targeting: true).example_targeting?).to be true
        end
      end
    end
  end

  describe "example_targeting_fallback (orchestration)" do
    it "defaults to :full_file" do
      config = described_class.new(skip_config_file: true)

      expect(config.example_targeting_fallback).to eq(:full_file)
    end

    it "accepts :unresolved" do
      config = described_class.new(example_targeting_fallback: :unresolved, skip_config_file: true)

      expect(config.example_targeting_fallback).to eq(:unresolved)
    end

    it "loads from YAML" do
      Dir.mktmpdir do |dir|
        Dir.chdir(dir) do
          File.write(".evilution.yml", "example_targeting_fallback: unresolved\n")

          expect(described_class.new.example_targeting_fallback).to eq(:unresolved)
        end
      end
    end
  end

  describe "example_targeting_cache (orchestration)" do
    it "defaults to { max_files: 50, max_blocks: 10000 }" do
      config = described_class.new(skip_config_file: true)

      expect(config.example_targeting_cache).to eq(max_files: 50, max_blocks: 10_000)
    end

    it "accepts overrides" do
      config = described_class.new(
        example_targeting_cache: { max_files: 100, max_blocks: 50_000 },
        skip_config_file: true
      )

      expect(config.example_targeting_cache).to eq(max_files: 100, max_blocks: 50_000)
    end

    it "merges partial overrides with defaults" do
      config = described_class.new(
        example_targeting_cache: { max_files: 100 },
        skip_config_file: true
      )

      expect(config.example_targeting_cache).to eq(max_files: 100, max_blocks: 10_000)
    end

    it "loads from YAML" do
      Dir.mktmpdir do |dir|
        Dir.chdir(dir) do
          File.write(".evilution.yml", <<~YAML)
            example_targeting_cache:
              max_files: 25
              max_blocks: 5000
          YAML

          expect(described_class.new.example_targeting_cache).to eq(max_files: 25, max_blocks: 5_000)
        end
      end
    end
  end

  describe "immutability" do
    it "is frozen after initialization" do
      config = described_class.new(skip_config_file: true)

      expect(config).to be_frozen
    end
  end
end
