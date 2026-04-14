# frozen_string_literal: true

require "tmpdir"
require "evilution/cli/parser/file_args"

RSpec.describe Evilution::CLI::Parser::FileArgs do
  describe ".parse" do
    it "returns empty files and ranges for empty input" do
      expect(described_class.parse([])).to eq([[], {}])
    end

    it "collects positional files" do
      files, ranges = described_class.parse(%w[lib/a.rb lib/b.rb])
      expect(files).to eq(%w[lib/a.rb lib/b.rb])
      expect(ranges).to eq({})
    end

    it "parses a single line" do
      _files, ranges = described_class.parse(["lib/a.rb:10"])
      expect(ranges["lib/a.rb"]).to eq(10..10)
    end

    it "parses a bounded range" do
      _files, ranges = described_class.parse(["lib/a.rb:15-30"])
      expect(ranges["lib/a.rb"]).to eq(15..30)
    end

    it "parses an open-ended range" do
      _files, ranges = described_class.parse(["lib/a.rb:15-"])
      expect(ranges["lib/a.rb"]).to eq(15..Float::INFINITY)
    end

    it "combines files with and without ranges" do
      files, ranges = described_class.parse(["lib/a.rb", "lib/b.rb:5-10"])
      expect(files).to eq(%w[lib/a.rb lib/b.rb])
      expect(ranges).to eq("lib/b.rb" => (5..10))
    end
  end

  describe ".expand_spec_dir" do
    it "returns all spec files under a directory" do
      Dir.mktmpdir do |dir|
        nested = File.join(dir, "nested")
        Dir.mkdir(nested)
        File.write(File.join(dir, "a_spec.rb"), "")
        File.write(File.join(nested, "b_spec.rb"), "")
        File.write(File.join(dir, "helper.rb"), "")

        specs = described_class.expand_spec_dir(dir)
        expect(specs).to contain_exactly(
          File.join(dir, "a_spec.rb"),
          File.join(nested, "b_spec.rb")
        )
      end
    end

    it "warns and returns an empty array when the path is not a directory" do
      expect { @specs = described_class.expand_spec_dir("/nonexistent/dir/xyz") }
        .to output(/is not a directory/).to_stderr
      expect(@specs).to eq([])
    end
  end
end
