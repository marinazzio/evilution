# frozen_string_literal: true

require "open3"
require "rbconfig"
require "evilution/infra_crash"

RSpec.describe Evilution::InfraCrash do
  describe "CLASSES" do
    it "lists the infrastructure crash classes" do
      expect(described_class::CLASSES).to eq(
        %w[
          Timeout::Error
          ActiveRecord::StatementTimeout
          ActiveRecord::Deadlocked
          ActiveRecord::ConnectionTimeoutError
          ActiveRecord::LockWaitTimeout
          SQLite3::BusyException
        ]
      )
    end

    it "is frozen" do
      expect(described_class::CLASSES).to be_frozen
    end
  end

  describe ".class_name?" do
    it "is true for every infrastructure crash class name" do
      expect(described_class::CLASSES.map { |name| described_class.class_name?(name) }).to all(be(true))
    end

    it "is false for a class name that says something about the mutation" do
      expect(described_class.class_name?("RuntimeError")).to be(false)
    end

    it "is false for a nil class name" do
      expect(described_class.class_name?(nil)).to be(false)
    end

    it "matches the exact name, not a namespace prefix" do
      expect(described_class.class_name?("Timeout")).to be(false)
    end
  end

  # The integrations load this module while evilution itself is still loading,
  # so it must need nothing beyond the top-level namespace.
  it "loads with only the top-level namespace defined" do
    lib = File.expand_path("../../lib", __dir__)
    script = 'require "evilution/infra_crash"; ' \
             'print Evilution::InfraCrash.class_name?("Timeout::Error"), " ", defined?(Evilution::Runner).inspect'
    out, err, status = Open3.capture3(RbConfig.ruby, "-I", lib, "-e", script)

    expect(status).to be_success, err
    expect(out).to eq("true nil")
  end
end
