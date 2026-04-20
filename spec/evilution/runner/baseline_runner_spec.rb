# frozen_string_literal: true

require "evilution/config"
require "evilution/runner"
require "evilution/runner/baseline_runner"
require "evilution/example_filter"

RSpec.describe Evilution::Runner::BaselineRunner do
  def config(**overrides)
    Evilution::Config.new(quiet: true, baseline: false, skip_config_file: true, **overrides)
  end

  describe "#integration_class" do
    it "returns the RSpec integration class when config.integration is :rspec" do
      runner = described_class.new(config(integration: :rspec))
      expect(runner.integration_class).to eq(Evilution::Integration::RSpec)
    end

    it "returns the Minitest integration class when config.integration is :minitest" do
      runner = described_class.new(config(integration: :minitest))
      expect(runner.integration_class).to eq(Evilution::Integration::Minitest)
    end

    it "raises Evilution::Error for an unknown integration" do
      cfg = Evilution::Config.allocate
      cfg.instance_variable_set(:@integration, :bogus)
      runner = described_class.new(cfg)
      expect { runner.integration_class }.to raise_error(Evilution::Error, /unknown integration/)
    end
  end

  describe "#build_integration" do
    it "constructs an integration with hooks and fallback options" do
      runner = described_class.new(
        config(integration: :rspec, fallback_to_full_suite: true, related_specs_heuristic: true),
        hooks: :hooks_obj
      )
      built = runner.build_integration
      expect(built).to be_a(Evilution::Integration::RSpec)
    end

    it "passes spec_files as test_files when not empty" do
      runner = described_class.new(config(integration: :rspec, spec_files: ["spec/a_spec.rb"]))
      expect(Evilution::Integration::RSpec).to receive(:new).with(
        hash_including(test_files: ["spec/a_spec.rb"])
      ).and_call_original
      runner.build_integration
    end

    it "passes nil test_files when spec_files is empty" do
      runner = described_class.new(config(integration: :rspec))
      expect(Evilution::Integration::RSpec).to receive(:new).with(
        hash_including(test_files: nil)
      ).and_call_original
      runner.build_integration
    end

    it "omits related_specs_heuristic for non-RSpec integrations" do
      runner = described_class.new(config(integration: :minitest))
      expect(Evilution::Integration::Minitest).to receive(:new) do |**kwargs|
        expect(kwargs).not_to have_key(:related_specs_heuristic)
        Evilution::Integration::Minitest.allocate
      end
      runner.build_integration
    end

    it "passes spec_selector for RSpec integration" do
      cfg = config(integration: :rspec)
      runner = described_class.new(cfg)
      expect(Evilution::Integration::RSpec).to receive(:new) do |**kwargs|
        expect(kwargs[:spec_selector]).to be(cfg.spec_selector)
        Evilution::Integration::RSpec.allocate
      end
      runner.build_integration
    end

    it "passes spec_selector for Minitest integration" do
      cfg = config(integration: :minitest)
      runner = described_class.new(cfg)
      expect(Evilution::Integration::Minitest).to receive(:new) do |**kwargs|
        expect(kwargs[:spec_selector]).to be(cfg.spec_selector)
        Evilution::Integration::Minitest.allocate
      end
      runner.build_integration
    end

    it "passes an ExampleFilter for RSpec when example_targeting enabled" do
      cfg = config(integration: :rspec, example_targeting: true)
      runner = described_class.new(cfg)
      expect(Evilution::Integration::RSpec).to receive(:new) do |**kwargs|
        expect(kwargs[:example_filter]).to be_a(Evilution::ExampleFilter)
        Evilution::Integration::RSpec.allocate
      end
      runner.build_integration
    end

    it "omits example_filter when example_targeting disabled" do
      cfg = config(integration: :rspec, example_targeting: false)
      runner = described_class.new(cfg)
      expect(Evilution::Integration::RSpec).to receive(:new) do |**kwargs|
        expect(kwargs[:example_filter]).to be_nil
        Evilution::Integration::RSpec.allocate
      end
      runner.build_integration
    end

    it "omits example_filter for Minitest integration regardless of example_targeting" do
      cfg = config(integration: :minitest, example_targeting: true)
      runner = described_class.new(cfg)
      expect(Evilution::Integration::Minitest).to receive(:new) do |**kwargs|
        expect(kwargs).not_to have_key(:example_filter)
        Evilution::Integration::Minitest.allocate
      end
      runner.build_integration
    end
  end

  describe "#call" do
    it "returns nil when config.baseline is false" do
      runner = described_class.new(config(baseline: false))
      expect(runner.call([:subject])).to be_nil
    end

    it "returns nil when there are no subjects even if baseline is true" do
      runner = described_class.new(config(baseline: true))
      expect(runner.call([])).to be_nil
    end

    it "invokes Evilution::Baseline with the integration's baseline_options" do
      runner = described_class.new(config(baseline: true, integration: :rspec, timeout: 7))
      baseline = instance_double(Evilution::Baseline, call: :ok)
      expect(Evilution::Baseline).to receive(:new)
        .with(hash_including(timeout: 7, runner: instance_of(Proc)))
        .and_return(baseline)
      expect(runner.call([:subject])).to eq(:ok)
    end
  end

  describe "#neutralization_resolver" do
    it "returns the spec_resolver from integration baseline_options when present" do
      klass = Class.new do
        def self.baseline_options
          { spec_resolver: :custom }
        end
      end
      runner = described_class.new(config)
      allow(runner).to receive(:integration_class).and_return(klass)
      expect(runner.neutralization_resolver).to eq(:custom)
    end

    it "falls back to a default SpecResolver when integration has none" do
      runner = described_class.new(config(integration: :rspec))
      expect(runner.neutralization_resolver).to be_a(Evilution::SpecResolver)
    end
  end

  describe "#neutralization_fallback_dir" do
    it "returns the fallback_dir from baseline_options when present" do
      klass = Class.new do
        def self.baseline_options
          { fallback_dir: "test" }
        end
      end
      runner = described_class.new(config)
      allow(runner).to receive(:integration_class).and_return(klass)
      expect(runner.neutralization_fallback_dir).to eq("test")
    end

    it "defaults to 'spec' when no fallback_dir is configured" do
      runner = described_class.new(config(integration: :rspec))
      expect(runner.neutralization_fallback_dir).to eq("spec")
    end
  end
end
