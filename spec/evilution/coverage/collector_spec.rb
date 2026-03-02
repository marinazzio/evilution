# frozen_string_literal: true

require "tempfile"

RSpec.describe Evilution::Coverage::Collector do
  subject(:collector) { described_class.new }

  describe "#call" do
    it "returns a Hash" do
      result = collector.call(test_files: [])

      expect(result).to be_a(Hash)
    end

    it "returns coverage data keyed by absolute file paths" do
      fixture = Tempfile.new(["coverage_fixture", ".rb"])
      fixture.write("x = 1 + 1\n")
      fixture.flush

      result = collector.call(test_files: [fixture.path])

      expect(result.keys).to all(be_a(String))
    ensure
      fixture.close!
    end

    it "records line-level hit counts for an executed file" do
      fixture = Tempfile.new(["coverage_fixture", ".rb"])
      fixture.write("x = 1 + 1\n")
      fixture.flush

      result = collector.call(test_files: [fixture.path])

      line_data = result[fixture.path]
      expect(line_data).to be_a(Array)
      # The single executable line should have been hit once
      expect(line_data.compact.first).to eq(1)
    ensure
      fixture.close!
    end

    it "returns an empty hash when no test files are given" do
      result = collector.call(test_files: [])

      expect(result).to eq({})
    end

    it "isolates coverage collection from the parent process" do
      # Calling the collector should not leave Coverage running in the parent
      fixture = Tempfile.new(["coverage_fixture", ".rb"])
      fixture.write("y = 2\n")
      fixture.flush

      collector.call(test_files: [fixture.path])

      # Coverage should not be running in the parent process after the call
      expect(Coverage.running?).to be false
    ensure
      fixture.close!
    end
  end
end
