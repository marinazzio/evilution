# frozen_string_literal: true

require "tempfile"
require "tmpdir"
require "fileutils"

RSpec.describe Evilution::Config do
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

    it "sets integration to :rspec" do
      expect(config.integration).to eq(:rspec)
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

    it "defaults hooks to empty hash" do
      config = described_class.new(skip_config_file: true)

      expect(config.hooks).to eq({})
    end

    it "accepts hooks configuration" do
      hooks_config = { worker_process_start: "config/hooks/worker.rb" }
      config = described_class.new(hooks: hooks_config, skip_config_file: true)

      expect(config.hooks).to eq(hooks_config)
    end

    it "rejects non-hash hooks value" do
      expect { described_class.new(hooks: "not_a_hash", skip_config_file: true) }
        .to raise_error(Evilution::ConfigError, /hooks must be a mapping/)
    end

    it "rejects array hooks value" do
      expect { described_class.new(hooks: ["file.rb"], skip_config_file: true) }
        .to raise_error(Evilution::ConfigError, /hooks must be a mapping/)
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

  describe "config file loading" do
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

    it "loads settings from config/evilution.yml" do
      Dir.mkdir("config")
      File.write("config/evilution.yml", "timeout: 20\n")

      config = described_class.new

      expect(config.timeout).to eq(20)
    end

    it "prefers .evilution.yml over config/evilution.yml" do
      File.write(".evilution.yml", "timeout: 30\n")
      Dir.mkdir("config")
      File.write("config/evilution.yml", "timeout: 20\n")

      config = described_class.new

      expect(config.timeout).to eq(30)
    end

    it "CLI options override file settings" do
      File.write(".evilution.yml", "timeout: 30\n")

      config = described_class.new(timeout: 5)

      expect(config.timeout).to eq(5)
    end

    it "handles empty config file gracefully" do
      File.write(".evilution.yml", "")

      config = described_class.new

      expect(config.timeout).to eq(30) # default
    end

    it "loads ignore_patterns from YAML" do
      yaml = <<~YAML
        ignore_patterns:
          - "call{name=info, receiver=call{name=logger}}"
          - "call{name=debug|warn}"
      YAML
      File.write(".evilution.yml", yaml)

      config = described_class.new

      expect(config.ignore_patterns).to eq([
                                             "call{name=info, receiver=call{name=logger}}",
                                             "call{name=debug|warn}"
                                           ])
    end

    it "defaults ignore_patterns to empty when not in YAML" do
      File.write(".evilution.yml", "timeout: 10\n")

      config = described_class.new

      expect(config.ignore_patterns).to eq([])
    end

    it "CLI options override ignore_patterns from file" do
      File.write(".evilution.yml", "ignore_patterns:\n  - \"call{name=log}\"\n")

      config = described_class.new(ignore_patterns: ["call{name=debug}"])

      expect(config.ignore_patterns).to eq(["call{name=debug}"])
    end

    it "loads skip_heredoc_literals from YAML" do
      File.write(".evilution.yml", "skip_heredoc_literals: true\n")

      config = described_class.new

      expect(config.skip_heredoc_literals?).to be true
    end

    it "defaults skip_heredoc_literals to false when not in YAML" do
      File.write(".evilution.yml", "timeout: 10\n")

      config = described_class.new

      expect(config.skip_heredoc_literals?).to be false
    end

    it "CLI options override skip_heredoc_literals from file" do
      File.write(".evilution.yml", "skip_heredoc_literals: true\n")

      config = described_class.new(skip_heredoc_literals: false)

      expect(config.skip_heredoc_literals?).to be false
    end

    it "loads related_specs_heuristic from YAML" do
      File.write(".evilution.yml", "related_specs_heuristic: true\n")

      config = described_class.new

      expect(config.related_specs_heuristic?).to be true
    end

    it "defaults related_specs_heuristic to false when not in YAML" do
      File.write(".evilution.yml", "timeout: 10\n")

      config = described_class.new

      expect(config.related_specs_heuristic?).to be false
    end

    it "CLI options override related_specs_heuristic from file" do
      File.write(".evilution.yml", "related_specs_heuristic: true\n")

      config = described_class.new(related_specs_heuristic: false)

      expect(config.related_specs_heuristic?).to be false
    end

    it "defaults fallback_to_full_suite to false" do
      config = described_class.new(skip_config_file: true)

      expect(config.fallback_to_full_suite?).to be false
    end

    it "loads fallback_to_full_suite from YAML" do
      File.write(".evilution.yml", "fallback_to_full_suite: true\n")

      config = described_class.new

      expect(config.fallback_to_full_suite?).to be true
    end

    it "CLI options override fallback_to_full_suite from file" do
      File.write(".evilution.yml", "fallback_to_full_suite: true\n")

      config = described_class.new(fallback_to_full_suite: false)

      expect(config.fallback_to_full_suite?).to be false
    end

    it "defaults spec_mappings to empty hash" do
      config = described_class.new(skip_config_file: true)

      expect(config.spec_mappings).to eq({})
    end

    it "defaults spec_pattern to nil" do
      config = described_class.new(skip_config_file: true)

      expect(config.spec_pattern).to be_nil
    end

    it "loads spec_mappings from YAML and normalizes string values to arrays" do
      File.write(".evilution.yml", <<~YAML)
        spec_mappings:
          app/controllers/games_controller.rb:
            - spec/requests/games_overlay_spec.rb
            - spec/requests/games_spec.rb
          lib/shared/util.rb: spec/lib/shared/util_spec.rb
      YAML

      config = described_class.new

      expect(config.spec_mappings).to eq(
        "app/controllers/games_controller.rb" => [
          "spec/requests/games_overlay_spec.rb",
          "spec/requests/games_spec.rb"
        ],
        "lib/shared/util.rb" => ["spec/lib/shared/util_spec.rb"]
      )
    end

    it "loads spec_pattern from YAML" do
      File.write(".evilution.yml", "spec_pattern: \"spec/requests/**/*_spec.rb\"\n")

      config = described_class.new

      expect(config.spec_pattern).to eq("spec/requests/**/*_spec.rb")
    end

    it "CLI options override spec_pattern from file" do
      File.write(".evilution.yml", "spec_pattern: \"spec/requests/**/*_spec.rb\"\n")

      config = described_class.new(spec_pattern: "spec/helpers/**/*_spec.rb")

      expect(config.spec_pattern).to eq("spec/helpers/**/*_spec.rb")
    end

    it "raises ConfigError when spec_mappings is not a hash" do
      File.write(".evilution.yml", "spec_mappings: nope\n")

      expect { described_class.new }.to raise_error(Evilution::ConfigError, /spec_mappings.*Hash/)
    end

    it "raises ConfigError when spec_mappings value is not a string or array" do
      expect do
        described_class.new(skip_config_file: true, spec_mappings: { "lib/foo.rb" => 42 })
      end.to raise_error(Evilution::ConfigError, /spec_mappings.*string or array/)
    end

    it "raises ConfigError when spec_mappings array contains non-strings" do
      expect do
        described_class.new(skip_config_file: true, spec_mappings: { "lib/foo.rb" => [42] })
      end.to raise_error(Evilution::ConfigError, /spec_mappings.*string/)
    end

    it "raises ConfigError when spec_pattern is not a string" do
      expect do
        described_class.new(skip_config_file: true, spec_pattern: 42)
      end.to raise_error(Evilution::ConfigError, /spec_pattern.*String/)
    end

    it "warns when spec_mappings entry references a missing file" do
      expect do
        described_class.new(
          skip_config_file: true,
          spec_mappings: { "lib/foo.rb" => "spec/missing_spec.rb" }
        )
      end.to output(%r{spec_mappings.*spec/missing_spec\.rb.*not found}).to_stderr
    end

    it "does not warn when all spec_mappings entries exist" do
      File.write("existing_spec.rb", "")

      expect do
        described_class.new(
          skip_config_file: true,
          spec_mappings: { "lib/foo.rb" => "existing_spec.rb" }
        )
      end.not_to output.to_stderr
    end

    it "normalizes leading ./ in spec_mappings keys" do
      File.write("existing_spec.rb", "")
      config = described_class.new(
        skip_config_file: true,
        spec_mappings: { "./lib/foo.rb" => "existing_spec.rb" }
      )

      expect(config.spec_mappings).to have_key("lib/foo.rb")
      expect(config.spec_mappings).not_to have_key("./lib/foo.rb")
    end

    it "normalizes absolute (pwd-prefixed) spec_mappings keys" do
      File.write("existing_spec.rb", "")
      config = described_class.new(
        skip_config_file: true,
        spec_mappings: { "#{Dir.pwd}/lib/foo.rb" => "existing_spec.rb" }
      )

      expect(config.spec_mappings).to have_key("lib/foo.rb")
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
    it "returns a YAML string with commented-out options" do
      template = described_class.default_template

      expect(template).to include("# timeout:")
      expect(template).to include("# format:")
    end
  end

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

  describe "fail_fast validation" do
    it "rejects zero" do
      expect { described_class.new(fail_fast: 0, skip_config_file: true) }
        .to raise_error(Evilution::ConfigError, /positive integer/)
    end

    it "rejects negative values" do
      expect { described_class.new(fail_fast: -1, skip_config_file: true) }
        .to raise_error(Evilution::ConfigError, /positive integer/)
    end

    it "rejects non-integer string values" do
      expect { described_class.new(fail_fast: "abc", skip_config_file: true) }
        .to raise_error(Evilution::ConfigError, /positive integer/)
    end

    it "rejects boolean values" do
      expect { described_class.new(fail_fast: true, skip_config_file: true) }
        .to raise_error(Evilution::ConfigError, /positive integer/)
    end
  end

  describe "jobs validation" do
    it "defaults to 1" do
      config = described_class.new(skip_config_file: true)
      expect(config.jobs).to eq(1)
    end

    it "accepts positive integers" do
      config = described_class.new(jobs: 4, skip_config_file: true)
      expect(config.jobs).to eq(4)
    end

    it "rejects zero" do
      expect { described_class.new(jobs: 0, skip_config_file: true) }
        .to raise_error(Evilution::ConfigError, /positive integer/)
    end

    it "rejects negative values" do
      expect { described_class.new(jobs: -1, skip_config_file: true) }
        .to raise_error(Evilution::ConfigError, /positive integer/)
    end

    it "rejects non-integer string values" do
      expect { described_class.new(jobs: "abc", skip_config_file: true) }
        .to raise_error(Evilution::ConfigError, /positive integer/)
    end

    it "rejects float values" do
      expect { described_class.new(jobs: 2.5, skip_config_file: true) }
        .to raise_error(Evilution::ConfigError, /positive integer/)
    end
  end

  describe "isolation validation" do
    it "defaults to :auto" do
      config = described_class.new(skip_config_file: true)
      expect(config.isolation).to eq(:auto)
    end

    it "accepts :fork" do
      config = described_class.new(isolation: :fork, skip_config_file: true)
      expect(config.isolation).to eq(:fork)
    end

    it "accepts :in_process" do
      config = described_class.new(isolation: :in_process, skip_config_file: true)
      expect(config.isolation).to eq(:in_process)
    end

    it "accepts string values and converts to symbol" do
      config = described_class.new(isolation: "fork", skip_config_file: true)
      expect(config.isolation).to eq(:fork)
    end

    it "rejects invalid values" do
      expect { described_class.new(isolation: :invalid, skip_config_file: true) }
        .to raise_error(Evilution::ConfigError, /isolation must be/)
    end

    it "rejects nil values" do
      expect { described_class.new(isolation: nil, skip_config_file: true) }
        .to raise_error(Evilution::ConfigError, /isolation must be/)
    end
  end

  describe "integration validation" do
    it "defaults to :rspec" do
      config = described_class.new(skip_config_file: true)
      expect(config.integration).to eq(:rspec)
    end

    it "accepts :minitest" do
      config = described_class.new(integration: :minitest, skip_config_file: true)
      expect(config.integration).to eq(:minitest)
    end

    it "accepts string values and converts to symbol" do
      config = described_class.new(integration: "minitest", skip_config_file: true)
      expect(config.integration).to eq(:minitest)
    end

    it "rejects invalid values" do
      expect { described_class.new(integration: :cucumber, skip_config_file: true) }
        .to raise_error(Evilution::ConfigError, /integration must be/)
    end

    it "rejects nil values" do
      expect { described_class.new(integration: nil, skip_config_file: true) }
        .to raise_error(Evilution::ConfigError, /integration must be/)
    end
  end

  describe "ignore_patterns" do
    it "defaults to empty array" do
      config = described_class.new(skip_config_file: true)

      expect(config.ignore_patterns).to eq([])
    end

    it "accepts an array of strings" do
      config = described_class.new(ignore_patterns: ["call{name=log}"], skip_config_file: true)

      expect(config.ignore_patterns).to eq(["call{name=log}"])
    end

    it "rejects non-string elements" do
      expect { described_class.new(ignore_patterns: [123], skip_config_file: true) }
        .to raise_error(Evilution::ConfigError, /ignore_patterns must be an array of strings/)
    end

    it "rejects hash elements" do
      expect { described_class.new(ignore_patterns: [{ name: "log" }], skip_config_file: true) }
        .to raise_error(Evilution::ConfigError, /ignore_patterns must be an array of strings/)
    end
  end

  describe "immutability" do
    it "is frozen after initialization" do
      config = described_class.new(skip_config_file: true)

      expect(config).to be_frozen
    end
  end
end
