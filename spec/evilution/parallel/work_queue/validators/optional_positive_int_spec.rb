# frozen_string_literal: true

require "spec_helper"
require "evilution/parallel/work_queue/validators/optional_positive_int"

RSpec.describe Evilution::Parallel::WorkQueue::Validators::OptionalPositiveInt do
  describe ".call!" do
    it "returns nil for nil" do
      expect(described_class.call!(:worker_max_items, nil)).to be_nil
    end

    it "returns nil for positive Integer" do
      expect(described_class.call!(:worker_max_items, 5)).to be_nil
    end

    it "raises for zero" do
      expect { described_class.call!(:worker_max_items, 0) }
        .to raise_error(ArgumentError, "worker_max_items must be nil or a positive integer, got 0")
    end

    it "raises for negative" do
      expect { described_class.call!(:worker_max_items, -1) }
        .to raise_error(ArgumentError, "worker_max_items must be nil or a positive integer, got -1")
    end

    it "raises for Float" do
      expect { described_class.call!(:worker_max_items, 2.0) }
        .to raise_error(ArgumentError, "worker_max_items must be nil or a positive integer, got 2.0")
    end
  end
end
