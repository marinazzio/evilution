# frozen_string_literal: true

require "spec_helper"
require "evilution/parallel/work_queue/validators/optional_positive_number"

RSpec.describe Evilution::Parallel::WorkQueue::Validators::OptionalPositiveNumber do
  describe ".call!" do
    it "returns nil for nil" do
      expect(described_class.call!(:item_timeout, nil)).to be_nil
    end

    it "returns nil for positive Integer" do
      expect(described_class.call!(:item_timeout, 5)).to be_nil
    end

    it "returns nil for positive Float" do
      expect(described_class.call!(:item_timeout, 2.5)).to be_nil
    end

    it "raises for zero" do
      expect { described_class.call!(:item_timeout, 0) }
        .to raise_error(ArgumentError, "item_timeout must be nil or a positive number, got 0")
    end

    it "raises for negative Float" do
      expect { described_class.call!(:item_timeout, -1.0) }
        .to raise_error(ArgumentError, "item_timeout must be nil or a positive number, got -1.0")
    end

    it "raises for String" do
      expect { described_class.call!(:item_timeout, "5") }
        .to raise_error(ArgumentError, "item_timeout must be nil or a positive number, got \"5\"")
    end
  end
end
