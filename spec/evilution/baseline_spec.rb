# frozen_string_literal: true

require "evilution/baseline"

RSpec.describe Evilution::Baseline do
  let(:spec_resolver) { instance_double(Evilution::SpecResolver) }

  subject(:baseline) { described_class.new(spec_resolver: spec_resolver, timeout: 5) }

  describe "#call" do
    let(:mutation1) { double("Mutation1", file_path: "lib/user.rb") }
    let(:mutation2) { double("Mutation2", file_path: "lib/user.rb") }
    let(:mutation3) { double("Mutation3", file_path: "lib/order.rb") }

    before do
      allow(spec_resolver).to receive(:call).with("lib/user.rb").and_return("spec/user_spec.rb")
      allow(spec_resolver).to receive(:call).with("lib/order.rb").and_return("spec/order_spec.rb")
    end

    it "returns a result with failed spec files" do
      allow(baseline).to receive(:run_spec_file).with("spec/user_spec.rb").and_return(false)
      allow(baseline).to receive(:run_spec_file).with("spec/order_spec.rb").and_return(true)

      result = baseline.call([mutation1, mutation2, mutation3])

      expect(result.failed_spec_files).to contain_exactly("spec/user_spec.rb")
    end

    it "deduplicates spec files from multiple mutations" do
      allow(baseline).to receive(:run_spec_file).with("spec/user_spec.rb").and_return(true)
      allow(baseline).to receive(:run_spec_file).with("spec/order_spec.rb").and_return(true)

      baseline.call([mutation1, mutation2, mutation3])

      expect(baseline).to have_received(:run_spec_file).with("spec/user_spec.rb").once
    end

    it "returns empty set when all specs pass" do
      allow(baseline).to receive(:run_spec_file).and_return(true)

      result = baseline.call([mutation1, mutation3])

      expect(result.failed_spec_files).to be_empty
    end

    it "returns empty result for empty mutations list" do
      result = baseline.call([])

      expect(result.failed_spec_files).to be_empty
    end

    it "treats unresolvable spec files as fallback 'spec' directory" do
      allow(spec_resolver).to receive(:call).with("lib/user.rb").and_return(nil)
      allow(baseline).to receive(:run_spec_file).with("spec").and_return(false)

      result = baseline.call([mutation1])

      expect(result.failed_spec_files).to contain_exactly("spec")
    end

    it "records duration" do
      allow(baseline).to receive(:run_spec_file).and_return(true)

      result = baseline.call([mutation1])

      expect(result.duration).to be >= 0
    end
  end

  describe Evilution::Baseline::Result do
    it "is frozen" do
      result = described_class.new(failed_spec_files: Set.new, duration: 0.0)

      expect(result).to be_frozen
    end

    it "exposes failed_spec_files" do
      result = described_class.new(failed_spec_files: Set["spec/user_spec.rb"], duration: 1.0)

      expect(result.failed_spec_files).to contain_exactly("spec/user_spec.rb")
    end

    it "exposes duration" do
      result = described_class.new(failed_spec_files: Set.new, duration: 2.5)

      expect(result.duration).to eq(2.5)
    end

    describe "#failed?" do
      it "returns true when there are failed spec files" do
        result = described_class.new(failed_spec_files: Set["spec/user_spec.rb"], duration: 0.0)

        expect(result).to be_failed
      end

      it "returns false when no spec files failed" do
        result = described_class.new(failed_spec_files: Set.new, duration: 0.0)

        expect(result).not_to be_failed
      end
    end
  end
end
