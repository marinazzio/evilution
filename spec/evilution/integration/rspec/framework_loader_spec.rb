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
end
