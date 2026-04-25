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

  it "creates and registers a detector on first call" do
    detector = lifecycle.current
    expect(detector).to eq(fake_detector)
    expect(RSpec.configuration).to have_received(:add_formatter).with(fake_detector).once
  end

  it "reuses the same detector and resets it on subsequent calls" do
    lifecycle.current
    lifecycle.current
    lifecycle.current

    expect(Evilution::Integration::CrashDetector).to have_received(:new).once
    expect(RSpec.configuration).to have_received(:add_formatter).once
    expect(fake_detector).to have_received(:reset).twice
  end
end
