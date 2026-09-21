# frozen_string_literal: true

require "spec_helper"
require "rspec/core"
require "evilution/integration/rspec/crash_detector_lifecycle"

RSpec.describe Evilution::Integration::RSpec::CrashDetectorLifecycle do
  let(:lifecycle) { described_class.new }
  let(:fake_detector) { instance_double(Evilution::Integration::CrashDetector, reset: nil) }

  before do
    allow(Evilution::Integration::CrashDetector).to receive(:new).and_return(fake_detector)
    allow(RSpec.configuration).to receive(:add_formatter)
  end

  it "creates a detector on first call" do
    expect(lifecycle.current).to eq(fake_detector)
  end

  # Its own buffer, not a shared or real stream: the detector's job is to
  # observe crashes, not to print anything.
  it "gives the detector a buffer of its own" do
    lifecycle.current

    expect(Evilution::Integration::CrashDetector).to have_received(:new).with(an_instance_of(StringIO))
  end

  it "reuses the same detector and resets it on subsequent calls" do
    lifecycle.current
    lifecycle.current
    lifecycle.current

    expect(Evilution::Integration::CrashDetector).to have_received(:new).once
    expect(fake_detector).to have_received(:reset).twice
  end

  # The run rebuilds RSpec's formatter loader so its formatters write to the
  # run's own streams (EV-m6xc / GH #1627), which drops whatever was registered
  # before it — so registration happens per run rather than once.
  it "registers the detector with RSpec each time it is asked" do
    lifecycle.register
    lifecycle.register

    expect(RSpec.configuration).to have_received(:add_formatter).with(fake_detector).twice
  end

  it "registers and returns the same detector" do
    expect(lifecycle.register).to eq(fake_detector)
  end

  it "does not register on its own" do
    lifecycle.current

    expect(RSpec.configuration).not_to have_received(:add_formatter)
  end
end
