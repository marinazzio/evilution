# frozen_string_literal: true

require "open3"
require "rbconfig"
require "evilution/integration/stop_policy"
require "evilution/integration/known_failures"

RSpec.describe Evilution::Integration::StopPolicy do
  let(:known) { Evilution::Integration::KnownFailures.new(%w[known]) }
  let(:enabled) { true }
  let(:infra_class) do
    Class.new(StandardError) { def self.name = "SQLite3::BusyException" }
  end

  subject(:policy) { described_class.new(enabled: enabled, known_failures: known) }

  describe "#decisive?" do
    it "is true for an assertion failure of an unknown test" do
      expect(policy.decisive?(id: "new")).to be true
    end

    it "is true for a crash that is not infrastructure" do
      expect(policy.decisive?(id: "new", exception: NoMethodError.new("x"))).to be true
    end

    it "is false for an infrastructure crash" do
      expect(policy.decisive?(id: "new", exception: infra_class.new("busy"))).to be false
    end

    it "is false for a test the baseline already saw failing" do
      expect(policy.decisive?(id: "known")).to be false
    end

    it "is false for a known test crashing on something that is not infrastructure" do
      expect(policy.decisive?(id: "known", exception: NoMethodError.new("x"))).to be false
    end
  end

  describe "#stopped?" do
    it "is false before anything is recorded" do
      expect(policy.stopped?).to be(false)
    end
  end

  describe "#record" do
    context "when disabled" do
      let(:enabled) { false }

      it "never stops" do
        expect(policy.record(id: "new")).to be false
        expect(policy).not_to be_stopped
      end
    end

    it "does not stop on a failure that is not decisive" do
      expect(policy.record(id: "known")).to be false
      expect(policy).not_to be_stopped
    end

    it "does not stop on an infrastructure crash" do
      expect(policy.record(id: "new", exception: infra_class.new("busy"))).to be false
      expect(policy).not_to be_stopped
    end

    it "stops on the first decisive failure" do
      expect(policy.record(id: "new")).to be true
      expect(policy).to be_stopped
    end

    it "is cleared by reset" do
      policy.record(id: "new")
      policy.reset
      expect(policy).not_to be_stopped
    end

    it "is reset to false, not just to something falsy" do
      policy.record(id: "new")
      policy.reset
      expect(policy.stopped?).to be(false)
    end
  end

  # The integration layer must not reach into the runner to judge a crash.
  it "judges an infrastructure crash without loading the runner" do
    lib = File.expand_path("../../../lib", __dir__)
    script = <<~RUBY
      require "evilution/version"
      require "evilution/integration/stop_policy"
      policy = Evilution::Integration::StopPolicy.new(
        enabled: true, known_failures: Evilution::Integration::KnownFailures.new([])
      )
      crash = Class.new(StandardError) { def self.name = "Timeout::Error" }
      print policy.decisive?(id: "new", exception: crash.new), " ", defined?(Evilution::Runner).inspect
    RUBY
    out, err, status = Open3.capture3(RbConfig.ruby, "-I", lib, "-e", script)

    expect(status).to be_success, err
    expect(out).to eq("false nil")
  end

  describe "DISABLED" do
    it "still judges failures, knowing of no baseline failures" do
      expect(described_class::DISABLED.decisive?(id: "new")).to be true
    end

    it "is frozen and never stops, however often it is used" do
      disabled = described_class::DISABLED
      expect(disabled).to be_frozen
      2.times do
        expect(disabled.record(id: "new")).to be false
        disabled.reset
        expect(disabled).not_to be_stopped
      end
    end
  end
end
