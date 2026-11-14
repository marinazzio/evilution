# frozen_string_literal: true

require "spec_helper"
require "evilution/integration/rspec/example_filter_applier"
require "evilution/example_filter"

RSpec.describe Evilution::Integration::RSpec::ExampleFilterApplier do
  let(:mutation) { Object.new }

  describe described_class::Identity do
    it "returns files unchanged" do
      applier = described_class.new
      expect(applier.call(mutation, ["spec/a_spec.rb", "spec/b_spec.rb"])).to eq(["spec/a_spec.rb", "spec/b_spec.rb"])
    end

    it "has nothing to warm" do
      expect(described_class.new.warm(mutation, ["spec/a_spec.rb"])).to be_nil
    end
  end

  describe described_class::Custom do
    it "delegates to the wrapped filter" do
      filter = ->(m, files) { ["filtered_for_#{m.object_id}"] + files }
      applier = described_class.new(filter)
      expect(applier.call(mutation, ["a"])).to eq(["filtered_for_#{mutation.object_id}", "a"])
    end

    it "warms the wrapped filter" do
      filter = instance_double(Evilution::ExampleFilter, warm: nil)

      described_class.new(filter).warm(mutation, ["a"])

      expect(filter).to have_received(:warm).with(mutation, ["a"])
    end

    it "has nothing to warm for a filter that keeps no cache" do
      applier = described_class.new(->(_, files) { files })

      expect { applier.warm(mutation, ["a"]) }.not_to raise_error
    end

    it "propagates nil from the filter" do
      filter = ->(_, _) { nil } # rubocop:disable Style/NilLambda
      applier = described_class.new(filter)
      expect(applier.call(mutation, ["a"])).to be_nil
    end
  end
end
