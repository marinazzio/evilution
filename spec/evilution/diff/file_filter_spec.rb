# frozen_string_literal: true

require "evilution/diff/file_filter"

RSpec.describe Evilution::Diff::FileFilter do
  subject(:filter) { described_class.new }

  let(:subject_in_range) do
    Evilution::Subject.new(
      name: "Foo#bar",
      file_path: "lib/foo.rb",
      line_number: 5,
      source: "def bar; end",
      node: nil
    )
  end

  let(:subject_outside_range) do
    Evilution::Subject.new(
      name: "Foo#baz",
      file_path: "lib/foo.rb",
      line_number: 20,
      source: "def baz; end",
      node: nil
    )
  end

  let(:subject_in_different_file) do
    Evilution::Subject.new(
      name: "Bar#qux",
      file_path: "lib/bar.rb",
      line_number: 3,
      source: "def qux; end",
      node: nil
    )
  end

  let(:changed_ranges) do
    [
      { file: "lib/foo.rb", lines: [3..10] }
    ]
  end

  describe "#filter" do
    it "includes subjects within changed line ranges" do
      result = filter.filter([subject_in_range], changed_ranges)

      expect(result).to eq([subject_in_range])
    end

    it "excludes subjects outside changed line ranges" do
      result = filter.filter([subject_outside_range], changed_ranges)

      expect(result).to eq([])
    end

    it "excludes subjects from files not in the diff" do
      result = filter.filter([subject_in_different_file], changed_ranges)

      expect(result).to eq([])
    end

    it "handles multiple subjects with mixed results" do
      subjects = [subject_in_range, subject_outside_range, subject_in_different_file]

      result = filter.filter(subjects, changed_ranges)

      expect(result).to eq([subject_in_range])
    end

    it "handles empty subjects list" do
      result = filter.filter([], changed_ranges)

      expect(result).to eq([])
    end

    it "handles empty changed_ranges" do
      result = filter.filter([subject_in_range], [])

      expect(result).to eq([])
    end

    it "handles multiple ranges for the same file" do
      ranges = [
        { file: "lib/foo.rb", lines: [1..3, 18..25] }
      ]

      result = filter.filter([subject_outside_range], ranges)

      expect(result).to eq([subject_outside_range])
    end
  end
end
