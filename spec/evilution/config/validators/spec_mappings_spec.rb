# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "fileutils"
require "evilution/config/validators/spec_mappings"

RSpec.describe Evilution::Config::Validators::SpecMappings do
  describe ".call" do
    around do |example|
      Dir.mktmpdir do |dir|
        Dir.chdir(dir) { example.run }
      end
    end

    it "returns {} for nil" do
      expect(described_class.call(nil)).to eq({})
    end

    it "raises when value is not a Hash" do
      expect { described_class.call("oops") }
        .to raise_error(Evilution::ConfigError, "spec_mappings must be a Hash, got String")
    end

    it "normalizes String values to single-element arrays" do
      FileUtils.mkdir_p("spec")
      File.write("spec/foo_spec.rb", "")
      result = described_class.call("lib/foo.rb" => "spec/foo_spec.rb")
      expect(result).to eq("lib/foo.rb" => ["spec/foo_spec.rb"])
    end

    it "strips absolute path prefix matching Dir.pwd" do
      FileUtils.mkdir_p("spec")
      File.write("spec/foo_spec.rb", "")
      abs = File.join(Dir.pwd, "lib/foo.rb")
      result = described_class.call(abs => ["spec/foo_spec.rb"])
      expect(result.keys).to eq(["lib/foo.rb"])
    end

    it "strips ./ prefix" do
      FileUtils.mkdir_p("spec")
      File.write("spec/foo_spec.rb", "")
      result = described_class.call("./lib/foo.rb" => ["spec/foo_spec.rb"])
      expect(result.keys).to eq(["lib/foo.rb"])
    end

    it "raises when array entry is not a String" do
      expect { described_class.call("lib/foo.rb" => [123]) }
        .to raise_error(Evilution::ConfigError,
                        %r{spec_mappings\["lib/foo\.rb"\] entries must be string paths, got Integer})
    end

    it "raises when value is neither String nor Array" do
      expect { described_class.call("lib/foo.rb" => 123) }
        .to raise_error(Evilution::ConfigError,
                        %r{spec_mappings\["lib/foo\.rb"\] must be a string or array of strings, got Integer})
    end

    it "warns on missing spec paths" do
      expect do
        described_class.call("lib/foo.rb" => ["spec/missing_spec.rb"])
      end.to output(%r{\[evilution\] spec_mappings\["lib/foo\.rb"\]: spec/missing_spec\.rb not found, skipping}).to_stderr
    end
  end
end
