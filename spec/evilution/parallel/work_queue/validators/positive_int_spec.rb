# frozen_string_literal: true

require "spec_helper"
require "evilution/parallel/work_queue/validators/positive_int"

RSpec.describe Evilution::Parallel::WorkQueue::Validators::PositiveInt do
  describe ".call!" do
    it "returns nil for a positive Integer" do
      expect(described_class.call!(:size, 1)).to be_nil
      expect(described_class.call!(:size, 42)).to be_nil
    end

    it "raises ArgumentError for zero" do
      expect { described_class.call!(:size, 0) }
        .to raise_error(ArgumentError, "size must be a positive integer, got 0")
    end

    it "raises ArgumentError for negative Integer" do
      expect { described_class.call!(:size, -3) }
        .to raise_error(ArgumentError, "size must be a positive integer, got -3")
    end

    it "raises ArgumentError for nil" do
      expect { described_class.call!(:size, nil) }
        .to raise_error(ArgumentError, "size must be a positive integer, got nil")
    end

    it "raises ArgumentError for Float" do
      expect { described_class.call!(:size, 1.5) }
        .to raise_error(ArgumentError, "size must be a positive integer, got 1.5")
    end

    it "raises ArgumentError for String" do
      expect { described_class.call!(:size, "1") }
        .to raise_error(ArgumentError, "size must be a positive integer, got \"1\"")
    end
  end
end
