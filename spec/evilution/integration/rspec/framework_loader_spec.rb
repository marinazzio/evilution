# frozen_string_literal: true

require "spec_helper"
require "evilution/integration/rspec/framework_loader"

RSpec.describe Evilution::Integration::RSpec::FrameworkLoader do
  let(:loader) { described_class.new }

  it "loaded? returns false initially" do
    expect(loader.loaded?).to be false
  end

  it "call loads rspec/core, registers crash detector, prepends spec/ to LOAD_PATH, sets loaded?" do
    allow(loader).to receive(:require).with("rspec/core").and_return(true)
    allow(Evilution::Integration::CrashDetector).to receive(:register_with_rspec)

    loader.call

    expect(loader).to have_received(:require).with("rspec/core")
    expect(Evilution::Integration::CrashDetector).to have_received(:register_with_rspec)
    expect($LOAD_PATH).to include(File.expand_path("spec"))
    expect(loader.loaded?).to be true
  end

  it "is idempotent: call twice does not require or register twice" do
    allow(loader).to receive(:require).with("rspec/core").and_return(true)
    allow(Evilution::Integration::CrashDetector).to receive(:register_with_rspec)

    loader.call
    loader.call

    expect(loader).to have_received(:require).with("rspec/core").once
    expect(Evilution::Integration::CrashDetector).to have_received(:register_with_rspec).once
  end

  it "translates LoadError into Evilution::Error" do
    allow(loader).to receive(:require).with("rspec/core").and_raise(LoadError, "no such file")

    expect { loader.call }.to raise_error(Evilution::Error, /rspec-core is required but not available: no such file/)
  end

  describe "spec/ LOAD_PATH handling" do
    let(:spec_dir) { File.expand_path("spec") }

    around do |example|
      had_spec_dir = $LOAD_PATH.include?(spec_dir)
      $LOAD_PATH.delete(spec_dir)
      example.run
    ensure
      $LOAD_PATH.delete(spec_dir)
      $LOAD_PATH.unshift(spec_dir) if had_spec_dir
    end

    it "prepends spec/ to the front of $LOAD_PATH when it is absent" do
      allow(loader).to receive(:require).with("rspec/core").and_return(true)
      allow(Evilution::Integration::CrashDetector).to receive(:register_with_rspec)

      loader.call

      expect($LOAD_PATH.first).to eq(spec_dir)
    end

    it "adds spec/ to $LOAD_PATH so it is present after the call" do
      allow(loader).to receive(:require).with("rspec/core").and_return(true)
      allow(Evilution::Integration::CrashDetector).to receive(:register_with_rspec)

      expect($LOAD_PATH).not_to include(spec_dir)

      loader.call

      expect($LOAD_PATH).to include(spec_dir)
    end

    it "does not duplicate spec/ in $LOAD_PATH when it is already present" do
      $LOAD_PATH.unshift(spec_dir)
      allow(loader).to receive(:require).with("rspec/core").and_return(true)
      allow(Evilution::Integration::CrashDetector).to receive(:register_with_rspec)

      loader.call

      expect($LOAD_PATH.count(spec_dir)).to eq(1)
    end
  end
end
