# frozen_string_literal: true

require "tmpdir"
require "yaml"
require "fileutils"

load File.expand_path("../../scripts/benchmark_density", __dir__)

RSpec.describe BenchmarkDensity do
  describe BenchmarkDensity::Config do
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

    def write_raw_config(content)
      path = File.join(@tmpdir, "config.yml")
      File.write(path, content)
      path
    end

    def valid_config_data
      {
        "project_root" => File.join(@tmpdir, "project"),
        "target_ratio" => 1.5,
        "reference_cmd" => %w[bundle exec tool run],
        "files" => [{ "path" => "app/models/user.rb", "reference_target" => "User" }]
      }
    end

    it "loads a valid config" do
      path = write_config(valid_config_data)

      config = described_class.new(path)

      expect(config.project_root).to eq(File.join(@tmpdir, "project"))
      expect(config.target_ratio).to eq(1.5)
      expect(config.reference_cmd).to eq(%w[bundle exec tool run])
      expect(config.files.length).to eq(1)
    end

    it "defaults target_ratio to 1.5" do
      data = valid_config_data.tap { |d| d.delete("target_ratio") }
      path = write_config(data)

      config = described_class.new(path)

      expect(config.target_ratio).to eq(1.5)
    end

    it "preserves explicit target_ratio of 0" do
      data = valid_config_data.merge("target_ratio" => 0)
      path = write_config(data)

      config = described_class.new(path)

      expect(config.target_ratio).to eq(0)
    end

    it "raises when YAML file is empty" do
      path = write_raw_config("")

      expect { described_class.new(path) }.to raise_error(
        BenchmarkDensity::ConfigError, /must contain a YAML mapping/
      )
    end

    it "raises when YAML is not a mapping" do
      path = write_raw_config("- item1\n- item2\n")

      expect { described_class.new(path) }.to raise_error(
        BenchmarkDensity::ConfigError, /must contain a YAML mapping/
      )
    end

    it "raises when project_root is nil" do
      data = valid_config_data.merge("project_root" => nil)
      path = write_config(data)

      expect { described_class.new(path) }.to raise_error(
        BenchmarkDensity::ConfigError, /project_root is required/
      )
    end

    it "raises when project_root does not exist" do
      data = valid_config_data.merge("project_root" => "/nonexistent/path")
      path = write_config(data)

      expect { described_class.new(path) }.to raise_error(
        BenchmarkDensity::ConfigError, /does not exist/
      )
    end

    it "raises when reference_cmd is empty" do
      data = valid_config_data.merge("reference_cmd" => [])
      path = write_config(data)

      expect { described_class.new(path) }.to raise_error(
        BenchmarkDensity::ConfigError, /reference_cmd is required/
      )
    end

    it "raises when files list is empty" do
      data = valid_config_data.merge("files" => [])
      path = write_config(data)

      expect { described_class.new(path) }.to raise_error(
        BenchmarkDensity::ConfigError, /files list is empty/
      )
    end

    it "raises when a file entry is missing path" do
      data = valid_config_data.merge("files" => [{ "reference_target" => "Foo" }])
      path = write_config(data)

      expect { described_class.new(path) }.to raise_error(
        BenchmarkDensity::ConfigError, /files\[0\] is missing required path/
      )
    end

    it "raises when a file entry is missing reference_target" do
      data = valid_config_data.merge("files" => [{ "path" => "foo.rb" }])
      path = write_config(data)

      expect { described_class.new(path) }.to raise_error(
        BenchmarkDensity::ConfigError, /files\[0\] is missing required reference_target/
      )
    end

    it "raises when a file entry is not a mapping" do
      data = valid_config_data.merge("files" => ["just_a_string"])
      path = write_config(data)

      expect { described_class.new(path) }.to raise_error(
        BenchmarkDensity::ConfigError, /files\[0\] must be a mapping/
      )
    end
  end

  describe BenchmarkDensity::EvilutionCounter do
    it "parses mutation count from subjects output" do
      counter = described_class.new("/tmp")
      output = <<~TEXT
        Evilution::Config  lib/evilution/config.rb:8  (12 mutations)
        Evilution::CLI  lib/evilution/cli.rb:15  (30 mutations)

        42 subjects, 42 mutations
      TEXT

      count = counter.send(:parse_subject_count, output)

      expect(count).to eq(42)
    end

    it "returns nil when output is unparseable" do
      counter = described_class.new("/tmp")

      count = counter.send(:parse_subject_count, "No subjects found")

      expect(count).to be_nil
    end
  end

  describe BenchmarkDensity::ReferenceCounter do
    it "parses mutation count from reference tool output" do
      counter = described_class.new("/tmp", ["echo"])
      output = "subjects: 5 mutations: 78"

      count = counter.send(:parse_mutation_count, output)

      expect(count).to eq(78)
    end

    it "returns nil when output is unparseable" do
      counter = described_class.new("/tmp", ["echo"])

      count = counter.send(:parse_mutation_count, "unexpected output")

      expect(count).to be_nil
    end
  end

  describe BenchmarkDensity::Runner do
    around do |example|
      Dir.mktmpdir do |dir|
        @tmpdir = dir
        FileUtils.mkdir_p(File.join(dir, "project"))
        example.run
      end
    end

    def make_config(files:, target_ratio: 1.5)
      project = File.join(@tmpdir, "project")
      path = File.join(@tmpdir, "config.yml")
      data = {
        "project_root" => project,
        "target_ratio" => target_ratio,
        "reference_cmd" => ["echo"],
        "files" => files
      }
      File.write(path, YAML.dump(data))
      BenchmarkDensity::Config.new(path)
    end

    describe "#passing?" do
      it "returns true when ratio is within target" do
        config = make_config(files: [{ "path" => "a.rb", "reference_target" => "A" }])
        runner = described_class.new(config: config)

        results = [{ path: "a.rb", evilution: 100, reference: 140 }]

        expect(runner.send(:passing?, results)).to be true
      end

      it "returns false when ratio exceeds target" do
        config = make_config(files: [{ "path" => "a.rb", "reference_target" => "A" }])
        runner = described_class.new(config: config)

        results = [{ path: "a.rb", evilution: 100, reference: 200 }]

        expect(runner.send(:passing?, results)).to be false
      end

      it "returns false when ratio exactly equals target" do
        config = make_config(files: [{ "path" => "a.rb", "reference_target" => "A" }])
        runner = described_class.new(config: config)

        results = [{ path: "a.rb", evilution: 100, reference: 150 }]

        expect(runner.send(:passing?, results)).to be false
      end

      it "returns false when evilution total is zero" do
        config = make_config(files: [{ "path" => "a.rb", "reference_target" => "A" }])
        runner = described_class.new(config: config)

        results = [{ path: "a.rb", evilution: 0, reference: 50 }]

        expect(runner.send(:passing?, results)).to be false
      end

      it "returns false when any result has nil counts" do
        config = make_config(
          files: [
            { "path" => "a.rb", "reference_target" => "A" },
            { "path" => "b.rb", "reference_target" => "B" }
          ]
        )
        runner = described_class.new(config: config)

        results = [
          { path: "a.rb", evilution: 100, reference: 140 },
          { path: "b.rb", evilution: nil, reference: 50 }
        ]

        expect(runner.send(:passing?, results)).to be false
      end

      it "returns false when ratio is slightly above target before rounding" do
        # 150 + 38 = 188 reference, 100 + 25 = 125 evilution => 188/125 = 1.504
        config = make_config(
          files: [
            { "path" => "a.rb", "reference_target" => "A" },
            { "path" => "b.rb", "reference_target" => "B" }
          ]
        )
        runner = described_class.new(config: config)

        results = [
          { path: "a.rb", evilution: 100, reference: 150 },
          { path: "b.rb", evilution: 25, reference: 38 }
        ]

        expect(runner.send(:passing?, results)).to be false
      end
    end

    describe "#compute_ratio" do
      it "computes ratio correctly" do
        config = make_config(files: [{ "path" => "a.rb", "reference_target" => "A" }])
        runner = described_class.new(config: config)

        expect(runner.send(:compute_ratio, 100, 186)).to eq(1.86)
      end

      it "returns nil when evilution is zero" do
        config = make_config(files: [{ "path" => "a.rb", "reference_target" => "A" }])
        runner = described_class.new(config: config)

        expect(runner.send(:compute_ratio, 0, 50)).to be_nil
      end

      it "returns nil when either value is nil" do
        config = make_config(files: [{ "path" => "a.rb", "reference_target" => "A" }])
        runner = described_class.new(config: config)

        expect(runner.send(:compute_ratio, nil, 50)).to be_nil
        expect(runner.send(:compute_ratio, 100, nil)).to be_nil
      end
    end

    describe "#compute_totals" do
      it "excludes errored rows from totals" do
        config = make_config(
          files: [
            { "path" => "a.rb", "reference_target" => "A" },
            { "path" => "b.rb", "reference_target" => "B" }
          ]
        )
        runner = described_class.new(config: config)

        results = [
          { path: "a.rb", evilution: 100, reference: 140 },
          { path: "b.rb", evilution: nil, reference: 50 }
        ]
        totals = runner.send(:compute_totals, results)

        expect(totals[:ev]).to eq(100)
        expect(totals[:ref]).to eq(140)
        expect(totals[:invalid]).to be true
        expect(totals[:error_count]).to eq(1)
      end

      it "marks as invalid when evilution total is zero" do
        config = make_config(files: [{ "path" => "a.rb", "reference_target" => "A" }])
        runner = described_class.new(config: config)

        results = [{ path: "a.rb", evilution: 0, reference: 50 }]
        totals = runner.send(:compute_totals, results)

        expect(totals[:invalid]).to be true
      end
    end
  end
end
