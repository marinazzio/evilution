# frozen_string_literal: true

require "evilution/integration/test_unit"
require "evilution/integration/test_unit/test_ids"

RSpec.describe Evilution::Integration::TestUnit::TestIds do
  def fault(test_name)
    double("Fault", test_name: test_name)
  end

  def result(failures: [], errors: [])
    double("TestResult", failures: failures, errors: errors)
  end

  describe ".faults" do
    it "gathers the failures and the errors" do
      failure = fault("test_a(CalcTest)")
      error = fault("test_b(CalcTest)")

      expect(described_class.faults(result(failures: [failure], errors: [error]))).to eq([failure, error])
    end
  end

  describe ".failed" do
    it "names every test that failed or raised" do
      run = result(failures: [fault("test_a(CalcTest)")], errors: [fault("test_b(CalcTest)")])

      expect(described_class.failed(run)).to eq(["test_a(CalcTest)", "test_b(CalcTest)"])
    end

    it "names nothing when nothing failed" do
      expect(described_class.failed(result)).to eq([])
    end
  end
end
