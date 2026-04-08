# frozen_string_literal: true

require "tmpdir"
require "yaml"
require "json"
require "fileutils"

load File.expand_path("../../scripts/compare_mutations", __dir__)

RSpec.describe CompareMutations do
  describe CompareMutations::MutationSet do
    it "builds from evilution JSON output" do
      data = [
        { "operator" => "true_swap", "line" => 10, "diff" => "- true\n+ false\n" },
        { "operator" => "noop_removal", "line" => 15, "diff" => "- foo\n" }
      ]

      set = described_class.from_json(data)

      expect(set.size).to eq(2)
    end

    it "normalizes diffs for comparison by stripping whitespace" do
      data1 = [{ "operator" => "op", "line" => 10, "diff" => "- true\n+ false\n" }]
      data2 = [{ "operator" => "op", "line" => 10, "diff" => "-true\n+false\n" }]

      set1 = described_class.from_json(data1)
      set2 = described_class.from_json(data2)

      expect(set1.fingerprints).to eq(set2.fingerprints)
    end

    it "distinguishes mutations on different lines" do
      data = [
        { "operator" => "op", "line" => 10, "diff" => "- x\n" },
        { "operator" => "op", "line" => 20, "diff" => "- x\n" }
      ]

      set = described_class.from_json(data)

      expect(set.fingerprints.uniq.size).to eq(2)
    end
  end

  describe CompareMutations::Comparison do
    def make_set(entries)
      CompareMutations::MutationSet.from_json(entries)
    end

    it "finds mutations in reference that are missing from evilution" do
      ev_data = [{ "operator" => "true_swap", "line" => 10, "diff" => "- true\n+ false\n" }]
      ref_data = [
        { "operator" => "true_swap", "line" => 10, "diff" => "- true\n+ false\n" },
        { "operator" => "negate", "line" => 20, "diff" => "- x > 0\n+ x <= 0\n" }
      ]

      comparison = described_class.new(evilution: make_set(ev_data), reference: make_set(ref_data))
      extra = comparison.extra_in_reference

      expect(extra.size).to eq(1)
      expect(extra.first["line"]).to eq(20)
    end

    it "returns empty when evilution covers all reference mutations" do
      data = [{ "operator" => "op", "line" => 10, "diff" => "- x\n+ y\n" }]

      comparison = described_class.new(evilution: make_set(data), reference: make_set(data))

      expect(comparison.extra_in_reference).to be_empty
    end

    it "finds mutations in evilution that reference lacks" do
      ev_data = [
        { "operator" => "op_a", "line" => 10, "diff" => "- a\n" },
        { "operator" => "op_b", "line" => 20, "diff" => "- b\n" }
      ]
      ref_data = [{ "operator" => "op_a", "line" => 10, "diff" => "- a\n" }]

      comparison = described_class.new(evilution: make_set(ev_data), reference: make_set(ref_data))

      expect(comparison.extra_in_evilution.size).to eq(1)
    end

    it "computes density ratio" do
      ev_data = [{ "operator" => "op", "line" => 10, "diff" => "- x\n" }]
      ref_data = [
        { "operator" => "op", "line" => 10, "diff" => "- x\n" },
        { "operator" => "op2", "line" => 20, "diff" => "- y\n" }
      ]

      comparison = described_class.new(evilution: make_set(ev_data), reference: make_set(ref_data))

      expect(comparison.density_ratio).to eq(2.0)
    end

    it "returns zero ratio when evilution has no mutations" do
      ref_data = [{ "operator" => "op", "line" => 10, "diff" => "- x\n" }]

      comparison = described_class.new(evilution: make_set([]), reference: make_set(ref_data))

      expect(comparison.density_ratio).to eq(0.0)
    end
  end

  describe CompareMutations::Catalog do
    it "groups extra mutations by operator" do
      extras = [
        { "operator" => "negate", "line" => 10, "diff" => "- x > 0\n+ x <= 0\n" },
        { "operator" => "negate", "line" => 20, "diff" => "- y > 0\n+ y <= 0\n" },
        { "operator" => "remove_call", "line" => 30, "diff" => "- foo.bar\n+ foo\n" }
      ]

      catalog = described_class.new(extras)
      grouped = catalog.by_operator

      expect(grouped["negate"].size).to eq(2)
      expect(grouped["remove_call"].size).to eq(1)
    end

    it "produces a summary with counts per operator" do
      extras = [
        { "operator" => "negate", "line" => 10, "diff" => "diff1" },
        { "operator" => "negate", "line" => 20, "diff" => "diff2" },
        { "operator" => "remove_call", "line" => 30, "diff" => "diff3" }
      ]

      catalog = described_class.new(extras)
      summary = catalog.summary

      expect(summary).to include({ operator: "negate", count: 2 })
      expect(summary).to include({ operator: "remove_call", count: 1 })
    end

    it "handles empty extras" do
      catalog = described_class.new([])

      expect(catalog.by_operator).to be_empty
      expect(catalog.summary).to be_empty
    end
  end

  describe CompareMutations::Config do
    around do |example|
      Dir.mktmpdir do |dir|
        @tmpdir = dir
        FileUtils.mkdir_p(File.join(dir, "project"))
        example.run
      end
    end

    def write_config(data)
      path = File.join(@tmpdir, "config.yml")
      File.write(path, YAML.dump(data))
      path
    end

    def valid_config_data
      {
        "project_root" => File.join(@tmpdir, "project"),
        "reference_cmd" => %w[bundle exec tool run],
        "output_dir" => File.join(@tmpdir, "results"),
        "files" => [{ "path" => "app/models/user.rb", "reference_target" => "User" }]
      }
    end

    it "loads a valid config" do
      path = write_config(valid_config_data)

      config = described_class.new(path)

      expect(config.project_root).to eq(File.join(@tmpdir, "project"))
      expect(config.files.length).to eq(1)
    end

    it "raises when config is not a mapping" do
      path = write_config("just a string")

      expect { described_class.new(path) }.to raise_error(
        CompareMutations::ConfigError, /must contain a YAML mapping/
      )
    end

    it "raises when project_root is missing" do
      data = valid_config_data.merge("project_root" => nil)
      path = write_config(data)

      expect { described_class.new(path) }.to raise_error(
        CompareMutations::ConfigError, /project_root is required/
      )
    end

    it "raises when files is empty" do
      data = valid_config_data.merge("files" => [])
      path = write_config(data)

      expect { described_class.new(path) }.to raise_error(
        CompareMutations::ConfigError, /files list is empty/
      )
    end

    it "raises when a file entry is missing path" do
      data = valid_config_data.merge("files" => [{ "reference_target" => "Foo" }])
      path = write_config(data)

      expect { described_class.new(path) }.to raise_error(
        CompareMutations::ConfigError, /files\[0\] is missing required path/
      )
    end
  end
end
