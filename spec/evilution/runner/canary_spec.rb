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

  def errored_result(message:, klass: "RuntimeError", backtrace: nil)
    Evilution::Result::MutationResult.new(
      mutation: instance_double(Evilution::Mutation), status: :error, duration: 0.0,
      error: Evilution::Result::ErrorInfo.from_fields(
        message: message, klass: klass, backtrace: backtrace
      )
    )
  end

  def stub_isolator_returning(result)
    isolator = instance_double(Evilution::Isolation::InProcess)
    allow(isolator).to receive(:call).and_return(result)
    isolator
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

    # EV-65nf / GH #1586: the failure previously reported only the status and a
    # list of four speculative causes, discarding the one field that names what
    # actually happened. Diagnosing GH #1581 meant rebuilding the canary by hand
    # to read result.error_message; none of the four guesses was the cause.
    describe "the underlying error" do
      it "names the error the child reported" do
        result = errored_result(
          message: "DEPRECATION WARNING: Grape::Path is deprecated!",
          klass: "ActiveSupport::DeprecationException"
        )
        canary = described_class.new(
          config: config, isolator: stub_isolator_returning(result),
          integration_class: Evilution::Integration::RSpec
        )

        expect { canary.call }.to raise_error(
          Evilution::Runner::Canary::Failed,
          /ActiveSupport::DeprecationException: DEPRECATION WARNING: Grape::Path is deprecated!/
        )
      end

      # MutationApplier packs "#{e.class}: #{e.message}" into the message field
      # while also filling error_class, so prefixing unconditionally would read
      # "NameError: NameError: ...".
      it "does not repeat a class the message already carries" do
        result = errored_result(
          message: "NameError: uninitialized constant Foo", klass: "NameError"
        )
        canary = described_class.new(
          config: config, isolator: stub_isolator_returning(result),
          integration_class: Evilution::Integration::RSpec
        )

        expect { canary.call }.to raise_error(Evilution::Runner::Canary::Failed, /NameError: uninitialized constant Foo/) { |error|
          expect(error.message).not_to include("NameError: NameError")
        }
      end

      # The frame is what identified the offending code in GH #1581 --
      # ConcernStateCleaner#call, which nothing else in the message pointed at.
      it "includes the first backtrace frame when the child reported one" do
        result = errored_result(
          message: "boom",
          backtrace: ["lib/evilution/integration/loading/concern_state_cleaner.rb:25:in 'call'", "other.rb:1"]
        )
        canary = described_class.new(
          config: config, isolator: stub_isolator_returning(result),
          integration_class: Evilution::Integration::RSpec
        )

        expect { canary.call }.to raise_error(Evilution::Runner::Canary::Failed, /concern_state_cleaner\.rb:25/)
      end

      it "reports the message alone when the child named no error class" do
        result = errored_result(message: "boom", klass: nil)
        canary = described_class.new(
          config: config, isolator: stub_isolator_returning(result),
          integration_class: Evilution::Integration::RSpec
        )

        expect { canary.call }.to raise_error(Evilution::Runner::Canary::Failed, /The child reported: boom/) { |error|
          expect(error.message).not_to match(/[A-Z]\w*(Error|Exception): boom/)
        }
      end

      it "falls back to the speculative causes when the error carries an empty message" do
        result = errored_result(message: "", klass: "RuntimeError")
        canary = described_class.new(
          config: config, isolator: stub_isolator_returning(result),
          integration_class: Evilution::Integration::RSpec
        )

        expect { canary.call }.to raise_error(Evilution::Runner::Canary::Failed, /Likely causes/)
      end

      it "omits the frame when the child reported an empty backtrace" do
        result = errored_result(message: "boom", backtrace: [])
        canary = described_class.new(
          config: config, isolator: stub_isolator_returning(result),
          integration_class: Evilution::Integration::RSpec
        )

        expect { canary.call }.to raise_error(Evilution::Runner::Canary::Failed, /boom/) { |error|
          expect(error.message).not_to include("(at ")
        }
      end

      it "omits the frame when the child reported no backtrace at all" do
        result = errored_result(message: "boom", backtrace: nil)
        canary = described_class.new(
          config: config, isolator: stub_isolator_returning(result),
          integration_class: Evilution::Integration::RSpec
        )

        expect { canary.call }.to raise_error(Evilution::Runner::Canary::Failed, /boom/) { |error|
          expect(error.message).not_to include("(at ")
        }
      end

      it "drops the speculative causes once it can name the real one" do
        result = errored_result(message: "boom")
        canary = described_class.new(
          config: config, isolator: stub_isolator_returning(result),
          integration_class: Evilution::Integration::RSpec
        )

        expect { canary.call }.to raise_error(Evilution::Runner::Canary::Failed, /boom/) { |error|
          expect(error.message).not_to include("Likely causes")
        }
      end

      # A :killed or :timeout canary carries no error, and there the guesses are
      # the only help available.
      it "keeps the speculative causes when the child reported no error" do
        canary = described_class.new(
          config: config, isolator: stub_isolator(:killed),
          integration_class: Evilution::Integration::RSpec
        )

        expect { canary.call }.to raise_error(Evilution::Runner::Canary::Failed, /Likely causes/)
      end

      it "still names the status either way" do
        result = errored_result(message: "boom")
        canary = described_class.new(
          config: config, isolator: stub_isolator_returning(result),
          integration_class: Evilution::Integration::RSpec
        )

        expect { canary.call }.to raise_error(Evilution::Runner::Canary::Failed, /scored :error instead of :survived/)
      end

      it "still points at --no-canary either way" do
        result = errored_result(message: "boom")
        canary = described_class.new(
          config: config, isolator: stub_isolator_returning(result),
          integration_class: Evilution::Integration::RSpec
        )

        expect { canary.call }.to raise_error(Evilution::Runner::Canary::Failed, /--no-canary/)
      end
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

    # for test-unit the canary previously wrote an RSpec
    # spec, which the test-unit integration cannot run -> scored :error ->
    # aborted every OOB test-unit run. It must emit a Test::Unit test instead.
    it "writes a test-unit test file when the integration is test_unit" do
      cfg = Evilution::Config.new(integration: :test_unit, skip_config_file: true)
      isolator = run_capturing(cfg: cfg)
      spec_path = recorded_integrations.last.test_files.first
      expect(File.basename(spec_path)).to end_with("_test.rb")
      expect(isolator.spec_file_source).to include("Test::Unit::TestCase")
      expect(isolator.spec_file_source).not_to include("RSpec.describe")
    end

    it "passes the configured hooks through to the integration" do
      hooks = Object.new
      run_capturing(hooks: hooks)
      expect(recorded_integrations.last.hooks).to be(hooks)
    end
  end
end
