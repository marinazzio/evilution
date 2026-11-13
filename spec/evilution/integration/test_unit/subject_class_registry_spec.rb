# frozen_string_literal: true

require "evilution/integration/test_unit"
require "evilution/integration/test_unit/framework_loader"
require "evilution/integration/test_unit/subject_class_registry"

RSpec.describe Evilution::Integration::TestUnit::SubjectClassRegistry do
  before(:context) do
    Evilution::Integration::TestUnit::FrameworkLoader.new.call
  end

  describe ".descendants" do
    it "lists test case classes at any depth, and no other class" do
      direct = Class.new(Test::Unit::TestCase)
      nested = Class.new(direct)
      plain = Class.new

      found = described_class.descendants

      expect(found).to include(direct, nested)
      expect(found).not_to include(plain, Test::Unit::TestCase)
    end
  end

  describe ".descendants without test-unit loaded" do
    it "is empty" do
      hide_const("Test::Unit::TestCase")

      expect(described_class.descendants).to eq([])
    end
  end

  describe ".newly_loaded" do
    it "returns the test case classes the block defined" do
      loaded = nil

      found = described_class.newly_loaded { loaded = Class.new(Test::Unit::TestCase) }

      expect(found).to eq([loaded])
    end

    # Loading a test file happens once per file in every mutation process; a
    # walk of the heap before and after each load would touch every page.
    it "does not walk the heap" do
      allow(ObjectSpace).to receive(:each_object).and_call_original

      described_class.newly_loaded { Class.new(Test::Unit::TestCase) }

      expect(ObjectSpace).not_to have_received(:each_object)
    end
  end
end
