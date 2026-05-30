# frozen_string_literal: true

require "evilution/integration/test_unit"

RSpec.describe Evilution::Integration::TestUnit, "framework loader (EV-8qiy)" do
  describe ".stub_autorun!" do
    around do |example|
      previous = nil
      previous = Test::Unit::AutoRunner.need_auto_run? if defined?(Test::Unit::AutoRunner)
      example.run
    ensure
      Test::Unit::AutoRunner.need_auto_run = previous if defined?(Test::Unit::AutoRunner) && !previous.nil?
    end

    it "disables Test::Unit::AutoRunner so its at_exit handler does not fire on evilution exit" do
      require "test-unit"
      Test::Unit::AutoRunner.need_auto_run = true

      described_class.stub_autorun!

      expect(Test::Unit::AutoRunner.need_auto_run?).to be false
    end

    it "is idempotent: calling twice keeps need_auto_run? false" do
      require "test-unit"
      described_class.stub_autorun!
      described_class.stub_autorun!

      expect(Test::Unit::AutoRunner.need_auto_run?).to be false
    end

    it "does not raise when test-unit has not been required yet" do
      # If test-unit was previously required in this process it stays loaded.
      # The stub should noop (and not raise) when AutoRunner isn't loaded.
      expect { described_class.stub_autorun! }.not_to raise_error
    end
  end

  describe "#ensure_framework_loaded (private)" do
    let(:integration) { described_class.allocate }

    it "requires test-unit and stubs autorun on first call" do
      allow(integration).to receive(:require).with("test-unit").and_return(true)
      allow(described_class).to receive(:stub_autorun!)

      integration.send(:ensure_framework_loaded)

      expect(integration).to have_received(:require).with("test-unit")
      expect(described_class).to have_received(:stub_autorun!)
    end

    it "is idempotent: second call does not re-require test-unit" do
      allow(integration).to receive(:require).with("test-unit").and_return(true)
      allow(described_class).to receive(:stub_autorun!)

      integration.send(:ensure_framework_loaded)
      integration.send(:ensure_framework_loaded)

      expect(integration).to have_received(:require).with("test-unit").once
      expect(described_class).to have_received(:stub_autorun!).once
    end

    it "translates LoadError into Evilution::Error with the test-unit gem name" do
      fresh = described_class.allocate
      allow(fresh).to receive(:require).with("test-unit").and_raise(LoadError, "cannot load such file -- test-unit")

      expect { fresh.send(:ensure_framework_loaded) }.to raise_error(
        Evilution::Error, /test-unit is required but not available.*cannot load such file -- test-unit/
      )
    end
  end
end
