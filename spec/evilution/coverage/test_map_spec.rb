# frozen_string_literal: true

RSpec.describe Evilution::Coverage::TestMap do
  let(:coverage_data) do
    {
      "/path/to/lib/foo.rb" => [nil, 1, 0, 3, nil, 0],
      "/path/to/lib/bar.rb" => [nil, 2, 1]
    }
  end

  subject(:test_map) { described_class.new(coverage_data) }

  describe "#covered?" do
    context "when the file is present in coverage data" do
      it "returns true for a line with a positive hit count" do
        expect(test_map.covered?("/path/to/lib/foo.rb", 2)).to be true
      end

      it "returns true for a line with a hit count greater than 1" do
        expect(test_map.covered?("/path/to/lib/foo.rb", 4)).to be true
      end

      it "returns false for a line with a hit count of zero" do
        expect(test_map.covered?("/path/to/lib/foo.rb", 3)).to be false
      end

      it "returns false for a line with a nil entry (non-executable line)" do
        expect(test_map.covered?("/path/to/lib/foo.rb", 1)).to be false
      end

      it "returns false for a nil line at the end of the array" do
        expect(test_map.covered?("/path/to/lib/foo.rb", 5)).to be false
      end

      it "returns false for a line number beyond the array length" do
        expect(test_map.covered?("/path/to/lib/foo.rb", 100)).to be false
      end
    end

    context "when the file is not present in coverage data" do
      it "returns false" do
        expect(test_map.covered?("/path/to/lib/unknown.rb", 1)).to be false
      end
    end

    context "with a second file in coverage data" do
      it "returns true for a covered line in bar.rb" do
        expect(test_map.covered?("/path/to/lib/bar.rb", 2)).to be true
      end

      it "returns false for a zero-hit line in bar.rb" do
        expect(test_map.covered?("/path/to/lib/foo.rb", 6)).to be false
      end
    end
  end
end
