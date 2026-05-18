# frozen_string_literal: true

require "evilution/runner/canary"
require "evilution/config"
require "evilution/integration/rspec"
require "evilution/integration/minitest"
require "evilution/isolation/in_process"
require "evilution/result/mutation_result"

# Drives the canary's test_command (so the integration is built and recorded)
# and snapshots the temp-dir state before the canary's ensure block removes
# it. Exposes the mutation the canary constructed and the on-disk files.
class CanarySpecCapturingIsolator
  attr_reader :mutation, :timeout, :class_file_exists, :class_file_source,
              :spec_file_exists, :spec_file_source

  def initialize(status:, integrations:)
    @status = status
    @integrations = integrations
  end

  def call(mutation:, test_command:, timeout:)
    @mutation = mutation
    @timeout = timeout
    test_command.call(mutation)
    snapshot_files
    Evilution::Result::MutationResult.new(
      mutation: mutation, status: @status, duration: 0.0
    )
  end

  private

  def snapshot_files
    class_path = @mutation.location.file_path
    @class_file_exists = File.exist?(class_path)
    @class_file_source = @class_file_exists ? File.read(class_path) : nil
    spec_path = @integrations.last.test_files.first
    @spec_file_exists = File.exist?(spec_path)
    @spec_file_source = @spec_file_exists ? File.read(spec_path) : nil
  end
end

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

  # Collects every RecordingIntegration instance the canary builds.
  let(:recorded_integrations) { [] }

  # An integration class that records its constructor arguments so the
  # canary's internal wiring (spec path, hooks) can be asserted without
  # running real tests.
  def recording_integration_class
    sink = recorded_integrations
    Class.new do
      attr_reader :test_files, :hooks

      define_method(:initialize) do |test_files:, hooks:|
        @test_files = test_files
        @hooks = hooks
        sink << self
      end

      def call(_mutation)
        :ok
      end
    end
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

  describe "synthetic mutation and file wiring" do
    def run_capturing(cfg: config, hooks: nil)
      isolator = CanarySpecCapturingIsolator.new(
        status: :survived, integrations: recorded_integrations
      )
      described_class.new(
        config: cfg, isolator: isolator,
        integration_class: recording_integration_class, hooks: hooks
      ).call
      isolator
    end

    it "writes the synthetic target class file to disk before isolation" do
      isolator = run_capturing
      expect(isolator.class_file_exists).to be(true)
      expect(isolator.class_file_source).to include("def __evilution_canary_probe")
    end

    it "writes the target class to a downcased file name" do
      isolator = run_capturing
      basename = File.basename(isolator.mutation.location.file_path)
      expect(basename).to eq(basename.downcase)
      expect(basename).to start_with("evilutioncanary_")
    end

    it "builds a mutation whose mutated source replaces :original with nil" do
      isolator = run_capturing
      expect(isolator.mutation.original_source).to include(":original")
      expect(isolator.mutation.mutated_source).to include("nil")
      expect(isolator.mutation.mutated_source).not_to include(":original")
    end

    it "uses a process- and random-derived suffix in the synthetic class name" do
      isolator = run_capturing
      class_name = isolator.mutation.subject.name.split("#").first
      expect(class_name).to match(/\AEvilutionCanary_#{Process.pid}_[0-9a-f]{8}\z/)
    end

    it "writes an RSpec spec file for the default rspec integration" do
      isolator = run_capturing
      spec_path = recorded_integrations.last.test_files.first
      expect(File.basename(spec_path)).to end_with("_spec.rb")
      expect(isolator.spec_file_exists).to be(true)
      expect(isolator.spec_file_source).to include("RSpec.describe")
    end

    it "writes a minitest test file when the integration is minitest" do
      cfg = Evilution::Config.new(integration: :minitest, skip_config_file: true)
      run_capturing(cfg: cfg)
      spec_path = recorded_integrations.last.test_files.first
      expect(File.basename(spec_path)).to end_with("_test.rb")
    end

    it "passes the configured hooks through to the integration" do
      hooks = Object.new
      run_capturing(hooks: hooks)
      expect(recorded_integrations.last.hooks).to be(hooks)
    end
  end
end
