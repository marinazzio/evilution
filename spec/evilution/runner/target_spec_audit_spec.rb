# frozen_string_literal: true

RSpec.describe Evilution::Runner::TargetSpecAudit do
  subject(:audit) { described_class.new(config) }

  # Config is frozen, and the real SpecSelector is driven by the filesystem, so
  # the audit is handed a config double whose selector stands in for "this file
  # resolves / does not resolve".
  let(:config) do
    instance_double(Evilution::Config, spec_selector: selector, fallback_to_full_suite?: fallback)
  end
  let(:fallback) { false }

  let(:selector) do
    instance_double(Evilution::SpecSelector).tap do |double|
      allow(double).to receive(:call) { |path| resolutions[path] }
    end
  end
  let(:resolutions) do
    {
      "lib/tested.rb" => ["spec/tested_spec.rb"],
      "lib/untested.rb" => nil,
      "lib/empty_result.rb" => []
    }
  end

  describe "#call" do
    it "returns the files that resolve to no spec" do
      expect(audit.call(["lib/tested.rb", "lib/untested.rb"])).to eq(["lib/untested.rb"])
    end

    # SpecSelector answers nil, but a custom resolver may answer an empty list.
    it "treats an empty resolution as unresolved" do
      expect(audit.call(["lib/empty_result.rb"])).to eq(["lib/empty_result.rb"])
    end

    it "returns an empty list when every file resolves" do
      expect(audit.call(["lib/tested.rb"])).to be_empty
    end

    it "returns an empty list for no files" do
      expect(audit.call([])).to be_empty
    end

    it "reports each file once, in sorted order" do
      files = ["lib/untested.rb", "lib/tested.rb", "lib/untested.rb", "lib/empty_result.rb"]

      expect(audit.call(files)).to eq(["lib/empty_result.rb", "lib/untested.rb"])
    end

    # With the fallback on, a file without its own spec runs against the whole
    # suite instead of being skipped, so nothing goes untested.
    context "when fallback_to_full_suite is set" do
      let(:fallback) { true }

      it "reports nothing" do
        expect(audit.call(["lib/untested.rb"])).to be_empty
      end
    end
  end
end
