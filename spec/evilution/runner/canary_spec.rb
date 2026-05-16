# frozen_string_literal: true

require "evilution/runner/canary"
require "evilution/config"
require "evilution/integration/rspec"
require "evilution/integration/minitest"
require "evilution/isolation/in_process"
require "evilution/result/mutation_result"

RSpec.describe Evilution::Runner::Canary do
  let(:config) { Evilution::Config.new(skip_config_file: true) }

  # A MutationResult with the given status; mutation is irrelevant to Canary.
  def result_with(status)
    Evilution::Result::MutationResult.new(
      mutation: instance_double(Evilution::Mutation), status: status, duration: 0.0
    )
  end

  def stub_isolator(status)
    isolator = instance_double(Evilution::Isolation::InProcess)
    allow(isolator).to receive(:call).and_return(result_with(status))
    isolator
  end

  describe "#call" do
    it "returns nil when the synthetic mutation is scored :survived" do
      canary = described_class.new(
        config: config, isolator: stub_isolator(:survived),
        integration_class: Evilution::Integration::RSpec
      )

      expect(canary.call).to be_nil
    end

    it "raises Canary::Failed when the synthetic mutation is not :survived" do
      canary = described_class.new(
        config: config, isolator: stub_isolator(:killed),
        integration_class: Evilution::Integration::RSpec
      )

      expect { canary.call }
        .to raise_error(Evilution::Runner::Canary::Failed, /scored :killed instead of :survived/)
    end

    it "aborts on :error too — anything but :survived fails the canary" do
      canary = described_class.new(
        config: config, isolator: stub_isolator(:error),
        integration_class: Evilution::Integration::RSpec
      )

      expect { canary.call }.to raise_error(Evilution::Runner::Canary::Failed)
    end

    it "passes the configured timeout to the isolator" do
      isolator = stub_isolator(:survived)
      cfg = Evilution::Config.new(timeout: 12, skip_config_file: true)
      described_class.new(
        config: cfg, isolator: isolator, integration_class: Evilution::Integration::RSpec
      ).call

      expect(isolator).to have_received(:call).with(hash_including(timeout: 12))
    end

    it "removes the temp directory afterward" do
      created = nil
      allow(Dir).to receive(:mktmpdir).and_wrap_original do |orig, *args|
        created = orig.call(*args)
      end
      described_class.new(
        config: config, isolator: stub_isolator(:survived),
        integration_class: Evilution::Integration::RSpec
      ).call

      expect(created).not_to be_nil
      expect(Dir.exist?(created)).to be false
    end

    it "removes the temp directory even when the canary fails" do
      created = nil
      allow(Dir).to receive(:mktmpdir).and_wrap_original do |orig, *args|
        created = orig.call(*args)
      end
      canary = described_class.new(
        config: config, isolator: stub_isolator(:killed),
        integration_class: Evilution::Integration::RSpec
      )

      expect { canary.call }.to raise_error(Evilution::Runner::Canary::Failed)
      expect(Dir.exist?(created)).to be false
    end

    # End-to-end against the real in_process isolator. Uses the minitest
    # integration deliberately: Integration::RSpec clears RSpec.world during a
    # run, which would eat examples from evilution's own suite. Minitest has no
    # such host-state hazard, so it is the safe framework for an in-suite e2e.
    it "scores the real synthetic mutation :survived end-to-end (minitest)" do
      cfg = Evilution::Config.new(integration: :minitest, skip_config_file: true)
      canary = described_class.new(
        config: cfg, isolator: Evilution::Isolation::InProcess.new,
        integration_class: Evilution::Integration::Minitest
      )

      expect(canary.call).to be_nil
    end
  end
end
