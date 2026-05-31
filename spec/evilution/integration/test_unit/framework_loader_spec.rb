# frozen_string_literal: true

require "evilution/integration/test_unit"
require "evilution/integration/test_unit/framework_loader"

RSpec.describe Evilution::Integration::TestUnit::FrameworkLoader do
  let(:loader) { described_class.new }

  describe "#loaded?" do
    it "returns false on a fresh instance" do
      expect(loader.loaded?).to be false
    end

    it "returns true after a successful #call" do
      allow(loader).to receive(:require).with("test-unit").and_return(true)
      allow(described_class).to receive(:stub_autorun!)

      loader.call

      expect(loader.loaded?).to be true
    end
  end

  describe "#call" do
    it "requires test-unit and stubs autorun" do
      allow(loader).to receive(:require).with("test-unit").and_return(true)
      allow(described_class).to receive(:stub_autorun!)

      loader.call

      expect(loader).to have_received(:require).with("test-unit")
      expect(described_class).to have_received(:stub_autorun!)
    end

    it "is idempotent: second call does not re-require test-unit" do
      allow(loader).to receive(:require).with("test-unit").and_return(true)
      allow(described_class).to receive(:stub_autorun!)

      loader.call
      loader.call

      expect(loader).to have_received(:require).with("test-unit").once
      expect(described_class).to have_received(:stub_autorun!).once
    end

    it "translates LoadError into Evilution::Error" do
      allow(loader).to receive(:require).with("test-unit").and_raise(LoadError, "cannot load such file -- test-unit")

      expect { loader.call }.to raise_error(
        Evilution::Error, /test-unit is required but not available.*cannot load such file -- test-unit/
      )
    end
  end

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

    it "does not raise when Test::Unit::AutoRunner is not loaded" do
      expect { described_class.stub_autorun! }.not_to raise_error
    end
  end
end
