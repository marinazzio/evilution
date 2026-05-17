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

    context "with schema_version declared (strict mode)" do
      it "returns the parsed Hash including schema_version when valid" do
        File.write(".evilution.yml", "schema_version: 1\ntimeout: 42\n")
        expect(described_class.load).to eq(schema_version: 1, timeout: 42)
      end

      it "raises ConfigError on an unknown top-level key" do
        File.write(".evilution.yml", "schema_version: 1\nunknown_key: value\n")
        expect { described_class.load }
          .to raise_error(Evilution::ConfigError, /unknown_key/)
      end

      it "lists the known keys in sorted order in the error message" do
        File.write(".evilution.yml", "schema_version: 1\nunknown_key: value\n")
        sorted = described_class::KNOWN_KEYS.sort.inspect
        expect { described_class.load }
          .to raise_error(Evilution::ConfigError, /Known keys: #{Regexp.escape(sorted)}/)
      end

      it "raises ConfigError when schema_version exceeds CURRENT_SCHEMA_VERSION" do
        File.write(".evilution.yml", "schema_version: 99\n")
        expect { described_class.load }
          .to raise_error(Evilution::ConfigError, /schema_version 99.*newer than this evilution gem/)
      end

      it "raises ConfigError when schema_version is 0" do
        File.write(".evilution.yml", "schema_version: 0\n")
        expect { described_class.load }
          .to raise_error(Evilution::ConfigError, /invalid schema_version 0.*positive Integer/)
      end

      it "raises ConfigError when schema_version is a negative integer" do
        File.write(".evilution.yml", "schema_version: -1\n")
        expect { described_class.load }
          .to raise_error(Evilution::ConfigError, /invalid schema_version -1.*positive Integer/)
      end

      it "raises ConfigError when schema_version is a String" do
        File.write(".evilution.yml", "schema_version: 'one'\n")
        expect { described_class.load }
          .to raise_error(Evilution::ConfigError, /invalid schema_version "one".*positive Integer/)
      end

      it "rejects target_files in YAML (CLI-positional only)" do
        File.write(".evilution.yml", "schema_version: 1\ntarget_files:\n  - lib/foo.rb\n")
        expect { described_class.load }
          .to raise_error(Evilution::ConfigError, /target_files/)
      end
    end

    context "without schema_version (lenient mode)" do
      it "returns the parsed Hash without raising" do
        File.write(".evilution.yml", "timeout: 42\n")
        expect(described_class.load).to eq(timeout: 42)
      end

      it "returns Hash including unknown keys (no validation applied)" do
        File.write(".evilution.yml", "timeout: 42\nunknown_key: value\n")
        expect(described_class.load).to eq(timeout: 42, unknown_key: "value")
      end
    end
  end
end
