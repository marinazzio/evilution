# frozen_string_literal: true

require "fileutils"
require "tmpdir"
require "evilution/integration/test_unit"
require "evilution/spec_resolver"

RSpec.describe Evilution::Integration::TestUnit, "spec resolver" do
  describe ".spec_resolver" do
    it "returns an Evilution::SpecResolver configured for the test-unit convention" do
      resolver = described_class.spec_resolver

      expect(resolver).to be_a(Evilution::SpecResolver)
      expect(resolver.instance_variable_get(:@test_dir)).to eq("test")
      expect(resolver.instance_variable_get(:@test_suffix)).to eq("_test.rb")
    end

    it "maps lib/foo.rb to test/foo_test.rb when the file exists" do
      Dir.mktmpdir do |dir|
        Dir.chdir(dir) do
          FileUtils.mkdir_p("test")
          FileUtils.touch("test/foo_test.rb")

          expect(described_class.spec_resolver.call("lib/foo.rb")).to eq("test/foo_test.rb")
        end
      end
    end

    it "maps app/models/user.rb to test/models/user_test.rb when the file exists" do
      Dir.mktmpdir do |dir|
        Dir.chdir(dir) do
          FileUtils.mkdir_p("test/models")
          FileUtils.touch("test/models/user_test.rb")

          expect(described_class.spec_resolver.call("app/models/user.rb")).to eq("test/models/user_test.rb")
        end
      end
    end

    it "returns nil when no matching test file exists" do
      Dir.mktmpdir do |dir|
        Dir.chdir(dir) do
          expect(described_class.spec_resolver.call("lib/missing.rb")).to be_nil
        end
      end
    end
  end

  describe ".baseline_options" do
    it "returns a Hash with runner, spec_resolver, and fallback_dir keys" do
      options = described_class.baseline_options

      expect(options).to include(:runner, :spec_resolver, :fallback_dir)
    end

    it "wires baseline_runner under :runner" do
      options = described_class.baseline_options

      expect(options[:runner]).to respond_to(:call)
    end

    it "wires spec_resolver under :spec_resolver" do
      options = described_class.baseline_options

      expect(options[:spec_resolver]).to be_a(Evilution::SpecResolver)
    end

    it "sets :fallback_dir to 'test'" do
      options = described_class.baseline_options

      expect(options[:fallback_dir]).to eq("test")
    end
  end
end
