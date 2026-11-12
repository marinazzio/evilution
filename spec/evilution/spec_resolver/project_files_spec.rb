# frozen_string_literal: true

require "tmpdir"
require "fileutils"
require "evilution/spec_resolver"

RSpec.describe Evilution::SpecResolver::ProjectFiles do
  # A file that exists under PROJECT_ROOT but not under the per-example CWD.
  let(:probe) { "spec/evilution/spec_resolver/project_files_spec.rb" }

  around do |example|
    previous = Evilution.instance_variable_get(:@in_isolated_worker)
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) { example.run }
    end
  ensure
    Evilution.instance_variable_set(:@in_isolated_worker, previous)
  end

  before { skip "PROJECT_ROOT probe missing" unless File.exist?(File.join(Evilution::PROJECT_ROOT, probe)) }

  describe ".read" do
    it "reads a CWD-relative file as binary" do
      File.write("a.rb", "café")

      expect(described_class.read("a.rb")).to eq("café".b)
    end

    it "returns an empty string for a missing file" do
      expect(described_class.read("missing.rb")).to eq("")
    end

    it "does not read PROJECT_ROOT when the isolated-worker flag is unset" do
      expect(described_class.read(probe)).to eq("")
    end

    it "reads PROJECT_ROOT when the flag is set and the CWD lookup fails" do
      Evilution.in_isolated_worker!

      expect(described_class.read(probe)).to include("RSpec.describe Evilution::SpecResolver::ProjectFiles")
    end

    it "prefers the CWD file over PROJECT_ROOT when the flag is set" do
      Evilution.in_isolated_worker!
      FileUtils.mkdir_p(File.dirname(probe))
      File.write(probe, "local")

      expect(described_class.read(probe)).to eq("local")
    end
  end

  describe ".directory?" do
    it "is true for a CWD directory" do
      FileUtils.mkdir_p("spec/x")

      expect(described_class.directory?("spec/x")).to be(true)
    end

    it "does not consult PROJECT_ROOT when the flag is unset" do
      expect(described_class.directory?("spec/evilution/spec_resolver")).to be(false)
    end

    it "consults PROJECT_ROOT when the flag is set" do
      Evilution.in_isolated_worker!

      expect(described_class.directory?("spec/evilution/spec_resolver")).to be(true)
    end
  end

  describe ".exist?" do
    it "does not consult PROJECT_ROOT when the flag is unset" do
      expect(described_class.exist?(probe)).to be(false)
    end

    it "consults PROJECT_ROOT when the flag is set" do
      Evilution.in_isolated_worker!

      expect(described_class.exist?(probe)).to be(true)
    end
  end

  describe ".glob" do
    it "globs the CWD when the flag is unset" do
      File.write("a_spec.rb", "")

      expect(described_class.glob("*_spec.rb")).to eq(["a_spec.rb"])
    end

    it "globs PROJECT_ROOT, returning root-relative paths, when the flag is set" do
      Evilution.in_isolated_worker!

      expect(described_class.glob("spec/evilution/spec_resolver/project_files_spec.rb")).to eq([probe])
    end
  end
end
