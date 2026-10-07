# frozen_string_literal: true

require "minitest"
require "evilution/integration/minitest"

RSpec.describe Evilution::Integration::Minitest::TestIds do
  def result(name, class_name: "CalcTest", failing: true, skipped: false)
    result = Minitest::Result.new(name)
    result.klass = class_name
    result.failures << Minitest::Assertion.new("no") if failing
    result.failures << Minitest::Skip.new("later") if skipped
    result
  end

  def summary(*results)
    instance_double(Minitest::SummaryReporter, results: results)
  end

  describe ".of" do
    it "names a test by its class and method" do
      expect(described_class.of(result("test_adds"))).to eq("CalcTest#test_adds")
    end

    # Before Minitest::Result there was no class_name: the test instance
    # itself was the result.
    it "names a result that is the test instance by the class of that instance" do
      legacy = Class.new do
        def self.name = "LegacyTest"
        def name = "test_adds"
      end

      expect(described_class.of(legacy.new)).to eq("LegacyTest#test_adds")
    end
  end

  describe ".failed" do
    it "names every test that failed" do
      failed = described_class.failed(summary(result("test_a"), result("test_b", class_name: "OtherTest")))

      expect(failed).to eq(%w[CalcTest#test_a OtherTest#test_b])
    end

    it "leaves out a skipped test" do
      skipped = result("test_later", failing: false, skipped: true)

      expect(described_class.failed(summary(result("test_a"), skipped))).to eq(%w[CalcTest#test_a])
    end

    it "names nothing when nothing failed" do
      expect(described_class.failed(summary)).to eq([])
    end
  end
end
