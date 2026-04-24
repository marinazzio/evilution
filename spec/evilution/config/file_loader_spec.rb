# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "evilution/config"

RSpec.describe Evilution::Config::FileLoader do
  around do |example|
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) { example.run }
    end
  end

  describe ".load" do
    it "returns {} when no config file exists" do
      expect(described_class.load).to eq({})
    end

    it "reads .evilution.yml when present" do
      File.write(".evilution.yml", "timeout: 42\n")
      expect(described_class.load).to eq(timeout: 42)
    end

    it "reads config/evilution.yml when .evilution.yml is absent" do
      Dir.mkdir("config")
      File.write("config/evilution.yml", "jobs: 4\n")
      expect(described_class.load).to eq(jobs: 4)
    end

    it "prefers .evilution.yml over config/evilution.yml" do
      Dir.mkdir("config")
      File.write(".evilution.yml", "timeout: 42\n")
      File.write("config/evilution.yml", "timeout: 99\n")
      expect(described_class.load).to eq(timeout: 42)
    end

    it "returns {} when YAML is not a Hash" do
      File.write(".evilution.yml", "- one\n- two\n")
      expect(described_class.load).to eq({})
    end

    it "wraps Psych::SyntaxError in Evilution::ConfigError" do
      File.write(".evilution.yml", "timeout: [unclosed\n")
      expect { described_class.load }.to raise_error(
        Evilution::ConfigError,
        /failed to parse config file \.evilution\.yml/
      )
    end

    it "wraps Psych::DisallowedClass in Evilution::ConfigError" do
      File.write(".evilution.yml", "timeout: !ruby/object:Object {}\n")
      expect { described_class.load }.to raise_error(
        Evilution::ConfigError,
        /failed to parse config file \.evilution\.yml/
      )
    end

    it "wraps SystemCallError in Evilution::ConfigError" do
      File.write(".evilution.yml", "timeout: 1\n")
      allow(YAML).to receive(:safe_load_file).and_raise(Errno::EACCES, "denied")
      expect { described_class.load }.to raise_error(
        Evilution::ConfigError,
        /cannot read config file \.evilution\.yml/
      )
    end
  end
end
