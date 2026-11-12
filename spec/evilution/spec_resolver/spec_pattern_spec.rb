# frozen_string_literal: true

require "evilution/spec_resolver"

RSpec.describe Evilution::SpecResolver::SpecPattern do
  describe ".filter" do
    let(:paths) { ["spec/a_spec.rb", "spec/x/b_spec.rb", "spec/c_spec.rb"] }

    it "returns the paths unchanged when there is no pattern" do
      expect(described_class.filter(paths, nil)).to equal(paths)
    end

    it "does not let a single star cross a directory separator" do
      expect(described_class.filter(paths, "spec/*_spec.rb")).to eq(["spec/a_spec.rb", "spec/c_spec.rb"])
    end

    it "lets a double star cross directories" do
      expect(described_class.filter(paths, "spec/**/b_spec.rb")).to eq(["spec/x/b_spec.rb"])
    end

    it "expands brace alternatives" do
      expect(described_class.filter(paths, "spec/{a,c}_spec.rb")).to eq(["spec/a_spec.rb", "spec/c_spec.rb"])
    end

    it "returns nothing when no path matches" do
      expect(described_class.filter(paths, "test/**/*_test.rb")).to eq([])
    end
  end
end
